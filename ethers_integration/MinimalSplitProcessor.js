//import { ethers } from 'ethers';

// ABI extracted from the contract (minimal version for key functions/events)
const CONTRACT_ABI = [
  'function pay(address seller, address paymentToken, uint256 amount, uint128 serviceId, uint256 invoiceId, bytes calldata permitData)',
  'function claim(address token)',
  'function getSellerInfo(address seller, address token) view returns (address wallet, uint256 balance)',
  'event Paid(address indexed buyer, address indexed seller, address indexed token, uint256 amount, uint128 serviceId, uint256 invoiceId, uint256 sellerAmount, uint256 companyAmount)',
  'event Claimed(address indexed seller, address indexed token, uint256 amount)',
  'function companyWallet() view returns (address)',
  'function companyFeeBps() view returns (uint256)'
];

// ERC20 ABI snippet for permit, approve, and nonce (supports both permit and traditional approve)
const ERC20_ABI = [
  'function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)',
  'function approve(address spender, uint256 amount)',
  'function nonces(address owner) view returns (uint256)',
  'function DOMAIN_SEPARATOR() view returns (bytes32)',
  'function name() view returns (string)',
  'function balanceOf(address owner) view returns (uint256)',
  'function allowance(address owner, address spender) view returns (uint256)'
];

/**
 * PaymentProcessor class for frontend integration.
 * Connects via MetaMask/ethers provider.
 * Handles pay with USDC permit (or fallback to approve if no permit support), claim, and queries.
 */
export class PaymentProcessor {
  constructor() {
    this.contractAddress = '0xB8beC05eeFC2dcE34044830e31612Ab3b9657DD3'; // Replace with actual deployed contract address
    this.usdcAddress = '0x036CbD53842c5426634e7929541eC2318f3dCF7e'; // USDC on Base sepolia
    this.contract = null;
    this.usdcContract = null;
    this.signer = null;
  }

  /**
   * Connect user's wallet (MetaMask or WalletConnect)
   * @returns {Promise<ethers.Signer>} - Signer instance
   */
  async connectWallet() {
    if (!window.ethereum) {
      alert("Please install MetaMask!");
      throw new Error("MetaMask not found");
    }

    // Request wallet connection
    await window.ethereum.request({ method: "eth_requestAccounts" });

    // Set provider and signer 
    const provider = new ethers.BrowserProvider(window.ethereum);
    this.signer = await provider.getSigner();
    const network = await this.signer.provider.getNetwork();
    console.log('Detected Chain ID:', network.chainId);
    if (network.chainId !== 84532n) { // change it mainnet chain id
    throw new Error(`Wrong network! Expected Base Sepolia (84532), got ${network.chainId}. Switch in MetaMask.`);
    }
    this.contract = new ethers.Contract(this.contractAddress, CONTRACT_ABI, this.signer);
    this.usdcContract = new ethers.Contract(this.usdcAddress, ERC20_ABI, this.signer);

    console.log("Connected:", await this.signer.getAddress());
    return this.signer;
  }

  /**
   * Pays for a service using USDC with permit (gasless approval) or fallback to traditional approve if no permit support.
   * @param {string} seller - Seller address (hex)
   * @param {bigint|string} amount - Amount in USDC (as string or bigint, e.g., '1000000' for 1 USDC with 6 decimals)
   * @param {number} serviceId - uint128 service ID
   * @param {number|string} invoiceId - uint256 invoice ID
   * @returns {Promise<ethers.TransactionResponse>} - Transaction response
   */
  async payWithPermit(seller, amount, serviceId, invoiceId) {
    if (!this.signer) throw new Error('Wallet not connected');
   // if (!ethers.isAddress(seller)) throw new Error('Invalid seller address');

    const amountWei = ethers.parseUnits(amount.toString(), 6); // USDC has 6 decimals
    const emptyPermitData = '0x'; // Empty bytes for no permit

    let permitData = emptyPermitData;
    let usesPermit = false;

    try {
      // Check for permit support by attempting to call DOMAIN_SEPARATOR
      await this.usdcContract.DOMAIN_SEPARATOR();
      console.log('Permit supported, using EIP-2612...');

      // Proceed with permit
      const deadline = Math.floor(Date.now() / 1000) + 60 * 20; // 20 minutes from now
      const nonce = await this.usdcContract.nonces(await this.signer.getAddress());
      const chainId = (await this.signer.provider.getNetwork()).chainId;
      const name = await this.usdcContract.name(); // 'USD Coin' or similar
      const version = '2'; // Standard for EIP-2612

      // EIP-712 Domain
      const domain = {
        name,
        version,
        chainId,
        verifyingContract: this.usdcAddress
      };

      // Permit typed data
      const types = {
        Permit: [
          { name: 'owner', type: 'address' },
          { name: 'spender', type: 'address' },
          { name: 'value', type: 'uint256' },
          { name: 'nonce', type: 'uint256' },
          { name: 'deadline', type: 'uint256' }
        ]
      };

      const value = {
        owner: await this.signer.getAddress(),
        spender: this.contractAddress,
        value: amountWei,
        nonce: nonce,
        deadline
      };

      // Sign the typed data
      const signature = await this.signer.signTypedData(domain, types, value);
      const { v, r, s } = ethers.Signature.from(signature);

      // Encode permitData as per contract
      permitData = ethers.AbiCoder.defaultAbiCoder().encode(
        ['address', 'address', 'uint256', 'uint256', 'uint8', 'bytes32', 'bytes32'],
        [value.owner, value.spender, value.value, value.deadline, v, r, s]
      );
      usesPermit = true;
    } catch (error) {
      console.log('Permit not supported, falling back to approve...');
      // Fallback: Approve the contract to spend the amount
      const approveTx = await this.usdcContract.approve(this.contractAddress, amountWei, {gasLimit: 100000});
      await approveTx.wait();
      console.log('Approval confirmed');
    }

    // Call pay (with permitData if using permit, else empty)
    const tx = await this.contract.pay(seller,
         this.usdcAddress,
          amountWei,
           BigInt(serviceId),
            BigInt(invoiceId),
             permitData,
             { gasLimit: 300000 });
    return tx;
  }

  /**
   * Claims seller balance for USDC.
   * @returns {Promise<ethers.TransactionResponse>} - Transaction response
   */
  async claim() {
    if (!this.signer) throw new Error('Wallet not connected');
    const tx = await this.contract.claim(this.usdcAddress);
    return tx;
  }

  /**
   * Gets seller info (balance) for USDC.
   * @param {string} seller - Seller address (hex)
   * @returns {Promise<{wallet: string, balance: bigint}>}
   */
  async getSellerBalance(seller) {
    if (!ethers.isAddress(seller)) throw new Error('Invalid seller address');
    const [wallet, balance] = await this.contract.getSellerInfo(seller, this.usdcAddress);
    return { wallet, balance };
  }

  /**
   * Listens for Paid event (optional, for UI updates).
   * @param {function} callback - Callback(event)
   * @returns {ethers.providers.EventListener} - Unsubscriber
   */
  onPayment(callback) {
    if (!this.contract) throw new Error('Contract not connected');
    return this.contract.on('Paid', callback);
  }

  /**
   * Listens for Claimed event.
   * @param {function} callback - Callback(event)
   * @returns {ethers.providers.EventListener} - Unsubscriber
   */
  onClaim(callback) {
    if (!this.contract) throw new Error('Contract not connected');
    return this.contract.on('Claimed', callback);
  }
}

// Usage example in frontend (e.g., React/Vanilla JS):
/*
const processor = new PaymentProcessor();

const signer = await processor.connectWallet();

const tx = await processor.payWithPermit('0x...Seller...', '1.5', 123, 456789);
await tx.wait();

const balance = await processor.getSellerBalance('0x...Seller...');
console.log(`Balance: ${ethers.formatUnits(balance.balance, 6)} USDC`);
*/