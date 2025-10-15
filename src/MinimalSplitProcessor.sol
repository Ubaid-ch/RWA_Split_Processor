// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title PaymentProcessor
 * @notice Handles service payments with a dynamic fee split between seller and company.
 *         Default: 95% seller / 5% company (configurable by owner).
 *         Supports ERC20 tokens and optional permit() approvals.
 *         Each payment can be tracked by serviceId and invoiceId.
 */
contract MinimalSplitProcessor is Ownable {
    using SafeERC20 for IERC20;

    /// @notice Address receiving the company commission
    address public companyWallet;

    /// @notice Company commission rate in basis points (e.g., 500 = 5%)
    uint256 public companyFeeBps = 500; // default 5%
    uint256 public constant BPS = 10000;

    /// @notice Seller token balances for later withdrawal
    mapping(address => mapping(address => uint256)) public sellerBalances; 
    /// seller => token => balance

    /// @notice Emitted when a payment is made
    event Paid(
        address indexed buyer,
        address indexed seller,
        address indexed token,
        uint256 amount,
        uint128 serviceId,
        uint256 invoiceId,
        uint256 sellerAmount,
        uint256 companyAmount
    );

    /// @notice Emitted when a seller claims their funds
    event Claimed(address indexed seller, address indexed token, uint256 amount);

    /// @notice Emitted when commission rate is updated
    event CommissionUpdated(uint256 oldRateBps, uint256 newRateBps);

    /// @notice Emitted when company wallet address is updated
    event CompanyWalletUpdated(address oldWallet, address newWallet);

    constructor(address _companyWallet) Ownable(msg.sender) {
        require(_companyWallet != address(0), "Invalid company wallet");
        companyWallet = _companyWallet;
    }

    /**
     * @notice Pay for a service using ERC20 tokens.
     * @param seller The address of the service provider receiving the main share of payment
     * @param paymentToken The ERC20 token address used for payment
     * @param amount The total payment amount
     * @param serviceId Unique identifier for the service being paid for
     * @param invoiceId Unique invoice or order number for this payment
     * @param permitData Optional ERC20 permit data (owner, spender, value, deadline, v, r, s)
     */
    function pay(
        address seller,
        address paymentToken,
        uint256 amount,
        uint128 serviceId,
        uint256 invoiceId,
        bytes calldata permitData
    ) external {
        require(seller != address(0), "Invalid seller");
        require(amount > 0, "Invalid amount");

        IERC20 token = IERC20(paymentToken);

        // Optional permit approval
        if (permitData.length > 0) {
            (
                address owner,
                address spender,
                uint256 value,
                uint256 deadline,
                uint8 v,
                bytes32 r,
                bytes32 s
            ) = abi.decode(permitData, (address, address, uint256, uint256, uint8, bytes32, bytes32));
            require(owner == msg.sender, "Invalid permit owner");
            require(spender == address(this), "Invalid permit spender");
            require(value >= amount, "Insufficient permit value");
            require(block.timestamp <= deadline, "Permit expired");

            IERC20Permit(paymentToken).permit(owner, spender, value, deadline, v, r, s);
        }

        // Transfer payment from buyer to contract
        token.safeTransferFrom(msg.sender, address(this), amount);

        // Calculate company and seller amounts dynamically
        uint256 companyAmount = (amount * companyFeeBps) / BPS;
        uint256 sellerAmount = amount - companyAmount;

        // Store seller balance for later claim
        sellerBalances[seller][paymentToken] += sellerAmount;

        // Transfer company fee immediately
        token.safeTransfer(companyWallet, companyAmount);

        emit Paid(
            msg.sender,
            seller,
            paymentToken,
            amount,
            serviceId,
            invoiceId,
            sellerAmount,
            companyAmount
        );
    }

    /**
     * @notice Seller claims their accumulated balance for a specific token.
     * @param token The ERC20 token to claim.
     */
    function claim(address token) external {
        uint256 balance = sellerBalances[msg.sender][token];
        require(balance > 0, "Nothing to claim");

        sellerBalances[msg.sender][token] = 0;
        IERC20(token).safeTransfer(msg.sender, balance);

        emit Claimed(msg.sender, token, balance);
    }

    /**
     * @notice Returns seller info: address and claimable balance for a specific token.
     */
    function getSellerInfo(address seller, address token)
        external
        view
        returns (address wallet, uint256 balance)
    {
        return (seller, sellerBalances[seller][token]);
    }

    /**
     * @notice Update the company fee rate (in basis points).
     * @param newFeeBps New company fee rate (e.g., 500 = 5%).
     */
    function setCompanyFee(uint256 newFeeBps) external onlyOwner {
        require(newFeeBps <= 1000, "Fee too high (max 10%)"); // safety limit
        emit CommissionUpdated(companyFeeBps, newFeeBps);
        companyFeeBps = newFeeBps;
    }

    /**
     * @notice Update the company wallet address.
     * @param newWallet New address for the company wallet.
     */
    function setCompanyWallet(address newWallet) external onlyOwner {
        require(newWallet != address(0), "Invalid wallet");
        emit CompanyWalletUpdated(companyWallet, newWallet);
        companyWallet = newWallet;
    }
}
