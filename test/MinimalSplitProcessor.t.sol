// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {MinimalSplitProcessor} from "../src/MinimalSplitProcessor.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/// @notice Mock USDC token (6 decimals, with permit)
contract MockUSDC is ERC20Permit {
    constructor() ERC20("USD Coin", "USDC") ERC20Permit("USD Coin") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MinimalSplitProcessorTest is Test {
    MinimalSplitProcessor public processor;
    MockUSDC public usdc;

    address public owner;
    address public companyWallet;
    address public buyer;
    address public seller;

    uint256 public constant COMPANY_FEE_BPS = 500; // 5%
    uint256 public constant BPS = 10000;

    // Private keys for permit signing
    uint256 public buyerPrivateKey = 0xB0B;
    uint256 public sellerPrivateKey = 0xA11CE;

    function setUp() public {
        owner = address(this);
        companyWallet = makeAddr("company");
        buyer = vm.addr(buyerPrivateKey);
        seller = vm.addr(sellerPrivateKey);

        processor = new MinimalSplitProcessor(companyWallet);
        usdc = new MockUSDC();

        // Mint USDC to buyer
        usdc.mint(buyer, 10000 * 10 ** 6); // 10,000 USDC
    }

    /* ============ USDC Payment Tests with Permit ============ */

    function test_Pay_WithPermit_USDC_Success() public {
        uint256 amount = 1000 * 10 ** 6; // 1000 USDC
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 permitHash = _getPermitHash(
            buyer,
            address(processor),
            amount,
            usdc.nonces(buyer),
            deadline
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(buyerPrivateKey, permitHash);

        bytes memory permitData = abi.encode(
            buyer,
            address(processor),
            amount,
            deadline,
            v,
            r,
            s
        );

        uint256 expectedCompanyAmount = (amount * COMPANY_FEE_BPS) / BPS; // 50 USDC
        uint256 expectedSellerAmount = amount - expectedCompanyAmount; // 950 USDC

        vm.expectEmit(true, true, true, true);
        emit MinimalSplitProcessor.Paid(
            buyer,
            seller,
            address(usdc),
            amount,
            1,
            100,
            expectedSellerAmount,
            expectedCompanyAmount
        );

        vm.prank(buyer);
        processor.pay(seller, address(usdc), amount, 1, 100, permitData);

        assertEq(processor.sellerBalances(seller, address(usdc)), expectedSellerAmount);
        assertEq(usdc.balanceOf(companyWallet), expectedCompanyAmount);
        assertEq(usdc.balanceOf(address(processor)), expectedSellerAmount);
    }

    function test_Pay_WithPermit_USDC_SmallAmount() public {
        uint256 amount = 10 * 10 ** 6; // 10 USDC
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 permitHash = _getPermitHash(
            buyer,
            address(processor),
            amount,
            usdc.nonces(buyer),
            deadline
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(buyerPrivateKey, permitHash);

        bytes memory permitData = abi.encode(
            buyer,
            address(processor),
            amount,
            deadline,
            v,
            r,
            s
        );

        uint256 expectedCompanyAmount = (amount * COMPANY_FEE_BPS) / BPS;
        uint256 expectedSellerAmount = amount - expectedCompanyAmount;

        vm.prank(buyer);
        processor.pay(seller, address(usdc), amount, 1, 100, permitData);

        assertEq(processor.sellerBalances(seller, address(usdc)), expectedSellerAmount);
        assertEq(usdc.balanceOf(companyWallet), expectedCompanyAmount);
    }

    function test_Pay_WithPermit_USDC_LargeAmount() public {
        uint256 amount = 5000 * 10 ** 6; // 5000 USDC
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 permitHash = _getPermitHash(
            buyer,
            address(processor),
            amount,
            usdc.nonces(buyer),
            deadline
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(buyerPrivateKey, permitHash);

        bytes memory permitData = abi.encode(
            buyer,
            address(processor),
            amount,
            deadline,
            v,
            r,
            s
        );

        uint256 expectedCompanyAmount = (amount * COMPANY_FEE_BPS) / BPS;
        uint256 expectedSellerAmount = amount - expectedCompanyAmount;

        vm.prank(buyer);
        processor.pay(seller, address(usdc), amount, 1, 100, permitData);

        assertEq(processor.sellerBalances(seller, address(usdc)), expectedSellerAmount);
        assertEq(usdc.balanceOf(companyWallet), expectedCompanyAmount);
    }

    function test_Pay_WithPermit_USDC_MultiplePayments() public {
        uint256 amount1 = 1000 * 10 ** 6;
        uint256 amount2 = 2000 * 10 ** 6;
        uint256 deadline = block.timestamp + 1 hours;

        // First payment
        bytes32 permitHash1 = _getPermitHash(
            buyer,
            address(processor),
            amount1,
            usdc.nonces(buyer),
            deadline
        );

        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(buyerPrivateKey, permitHash1);

        bytes memory permitData1 = abi.encode(
            buyer,
            address(processor),
            amount1,
            deadline,
            v1,
            r1,
            s1
        );

        vm.prank(buyer);
        processor.pay(seller, address(usdc), amount1, 1, 100, permitData1);

        // Second payment (nonce incremented)
        bytes32 permitHash2 = _getPermitHash(
            buyer,
            address(processor),
            amount2,
            usdc.nonces(buyer),
            deadline
        );

        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(buyerPrivateKey, permitHash2);

        bytes memory permitData2 = abi.encode(
            buyer,
            address(processor),
            amount2,
            deadline,
            v2,
            r2,
            s2
        );

        vm.prank(buyer);
        processor.pay(seller, address(usdc), amount2, 2, 101, permitData2);

        uint256 totalAmount = amount1 + amount2;
        uint256 expectedCompanyTotal = (totalAmount * COMPANY_FEE_BPS) / BPS;
        uint256 expectedSellerTotal = totalAmount - expectedCompanyTotal;

        assertEq(processor.sellerBalances(seller, address(usdc)), expectedSellerTotal);
        assertEq(usdc.balanceOf(companyWallet), expectedCompanyTotal);
    }

    function test_Pay_WithPermit_USDC_RevertsInvalidOwner() public {
        uint256 amount = 1000 * 10 ** 6;
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 permitHash = _getPermitHash(
            buyer,
            address(processor),
            amount,
            usdc.nonces(buyer),
            deadline
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(buyerPrivateKey, permitHash);

        // Wrong owner in permit data
        bytes memory permitData = abi.encode(
            seller, // wrong owner
            address(processor),
            amount,
            deadline,
            v,
            r,
            s
        );

        vm.prank(buyer);
        vm.expectRevert("Invalid permit owner");
        processor.pay(seller, address(usdc), amount, 1, 100, permitData);
    }

    function test_Pay_WithPermit_USDC_RevertsInvalidSpender() public {
        uint256 amount = 1000 * 10 ** 6;
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 permitHash = _getPermitHash(
            buyer,
            address(processor),
            amount,
            usdc.nonces(buyer),
            deadline
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(buyerPrivateKey, permitHash);

        bytes memory permitData = abi.encode(
            buyer,
            seller, // wrong spender
            amount,
            deadline,
            v,
            r,
            s
        );

        vm.prank(buyer);
        vm.expectRevert("Invalid permit spender");
        processor.pay(seller, address(usdc), amount, 1, 100, permitData);
    }

    function test_Pay_WithPermit_USDC_RevertsInsufficientValue() public {
        uint256 amount = 1000 * 10 ** 6;
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 permitHash = _getPermitHash(
            buyer,
            address(processor),
            amount,
            usdc.nonces(buyer),
            deadline
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(buyerPrivateKey, permitHash);

        bytes memory permitData = abi.encode(
            buyer,
            address(processor),
            amount - 1, // insufficient value
            deadline,
            v,
            r,
            s
        );

        vm.prank(buyer);
        vm.expectRevert("Insufficient permit value");
        processor.pay(seller, address(usdc), amount, 1, 100, permitData);
    }

    function test_Pay_WithPermit_USDC_RevertsExpiredDeadline() public {
        uint256 amount = 1000 * 10 ** 6;
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 permitHash = _getPermitHash(
            buyer,
            address(processor),
            amount,
            usdc.nonces(buyer),
            deadline
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(buyerPrivateKey, permitHash);

        bytes memory permitData = abi.encode(
            buyer,
            address(processor),
            amount,
            deadline,
            v,
            r,
            s
        );

        // Warp time past deadline
        vm.warp(deadline + 1);

        vm.prank(buyer);
        vm.expectRevert("Permit expired");
        processor.pay(seller, address(usdc), amount, 1, 100, permitData);
    }

    function test_Pay_WithPermit_USDC_RevertsInvalidSignature() public {
        uint256 amount = 1000 * 10 ** 6;
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 permitHash = _getPermitHash(
            buyer,
            address(processor),
            amount,
            usdc.nonces(buyer),
            deadline
        );

        // Sign with wrong private key
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(sellerPrivateKey, permitHash);

        bytes memory permitData = abi.encode(
            buyer,
            address(processor),
            amount,
            deadline,
            v,
            r,
            s
        );

        vm.prank(buyer);
        // Will revert in permit() call with ERC20Permit's error
        vm.expectRevert();
        processor.pay(seller, address(usdc), amount, 1, 100, permitData);
    }

    function test_Pay_WithPermit_USDC_RevertsReusedSignature() public {
        uint256 amount = 1000 * 10 ** 6;
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 permitHash = _getPermitHash(
            buyer,
            address(processor),
            amount,
            usdc.nonces(buyer),
            deadline
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(buyerPrivateKey, permitHash);

        bytes memory permitData = abi.encode(
            buyer,
            address(processor),
            amount,
            deadline,
            v,
            r,
            s
        );

        // First payment succeeds
        vm.prank(buyer);
        processor.pay(seller, address(usdc), amount, 1, 100, permitData);

        // Try to reuse same signature (nonce already used)
        vm.prank(buyer);
        vm.expectRevert();
        processor.pay(seller, address(usdc), amount, 2, 101, permitData);
    }

    function test_Pay_WithPermit_USDC_HighValuePermit() public {
        uint256 permitValue = 10000 * 10 ** 6; // Permit for 10,000 USDC
        uint256 paymentAmount = 1000 * 10 ** 6; // Only pay 1,000 USDC
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 permitHash = _getPermitHash(
            buyer,
            address(processor),
            permitValue,
            usdc.nonces(buyer),
            deadline
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(buyerPrivateKey, permitHash);

        bytes memory permitData = abi.encode(
            buyer,
            address(processor),
            permitValue,
            deadline,
            v,
            r,
            s
        );

        uint256 expectedCompanyAmount = (paymentAmount * COMPANY_FEE_BPS) / BPS;
        uint256 expectedSellerAmount = paymentAmount - expectedCompanyAmount;

        vm.prank(buyer);
        processor.pay(seller, address(usdc), paymentAmount, 1, 100, permitData);

        assertEq(processor.sellerBalances(seller, address(usdc)), expectedSellerAmount);
        assertEq(usdc.balanceOf(companyWallet), expectedCompanyAmount);
    }

    function test_Pay_WithPermit_USDC_DifferentFeeRates() public {
        // Test with 3% fee
        processor.setCompanyFee(300);

        uint256 amount = 1000 * 10 ** 6;
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 permitHash = _getPermitHash(
            buyer,
            address(processor),
            amount,
            usdc.nonces(buyer),
            deadline
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(buyerPrivateKey, permitHash);

        bytes memory permitData = abi.encode(
            buyer,
            address(processor),
            amount,
            deadline,
            v,
            r,
            s
        );

        uint256 expectedCompanyAmount = (amount * 300) / BPS; // 30 USDC
        uint256 expectedSellerAmount = amount - expectedCompanyAmount; // 970 USDC

        vm.prank(buyer);
        processor.pay(seller, address(usdc), amount, 1, 100, permitData);

        assertEq(processor.sellerBalances(seller, address(usdc)), expectedSellerAmount);
        assertEq(usdc.balanceOf(companyWallet), expectedCompanyAmount);
    }

    function test_Claim_USDC_AfterPermitPayment() public {
        uint256 amount = 1000 * 10 ** 6;
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 permitHash = _getPermitHash(
            buyer,
            address(processor),
            amount,
            usdc.nonces(buyer),
            deadline
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(buyerPrivateKey, permitHash);

        bytes memory permitData = abi.encode(
            buyer,
            address(processor),
            amount,
            deadline,
            v,
            r,
            s
        );

        vm.prank(buyer);
        processor.pay(seller, address(usdc), amount, 1, 100, permitData);

        uint256 expectedSellerAmount = amount - (amount * COMPANY_FEE_BPS) / BPS;
        uint256 sellerBalanceBefore = usdc.balanceOf(seller);

        vm.expectEmit(true, true, false, true);
        emit MinimalSplitProcessor.Claimed(seller, address(usdc), expectedSellerAmount);

        vm.prank(seller);
        processor.claim(address(usdc));

        assertEq(usdc.balanceOf(seller), sellerBalanceBefore + expectedSellerAmount);
        assertEq(processor.sellerBalances(seller, address(usdc)), 0);
    }

    /* ============ Fuzz Tests ============ */

    function testFuzz_Pay_WithPermit_USDC(uint256 amount) public {
        amount = bound(amount, 1 * 10 ** 6, 10000 * 10 ** 6); // 1 to 10,000 USDC
        uint256 deadline = block.timestamp + 1 hours;

        bytes32 permitHash = _getPermitHash(
            buyer,
            address(processor),
            amount,
            usdc.nonces(buyer),
            deadline
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(buyerPrivateKey, permitHash);

        bytes memory permitData = abi.encode(
            buyer,
            address(processor),
            amount,
            deadline,
            v,
            r,
            s
        );

        uint256 expectedCompanyAmount = (amount * COMPANY_FEE_BPS) / BPS;
        uint256 expectedSellerAmount = amount - expectedCompanyAmount;

        vm.prank(buyer);
        processor.pay(seller, address(usdc), amount, 1, 100, permitData);

        assertEq(processor.sellerBalances(seller, address(usdc)), expectedSellerAmount);
        assertEq(usdc.balanceOf(companyWallet), expectedCompanyAmount);
    }

    /* ============ Helper Functions ============ */

    function _getPermitHash(
        address owner,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner,
                spender,
                value,
                nonce,
                deadline
            )
        );

        bytes32 domainSeparator = usdc.DOMAIN_SEPARATOR();

        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }
}