# MinimalSplitProcessor

A smart contract for handling service payments with dynamic fee splitting between sellers and the company.

## Features

- **Fee Splitting**: Automatically splits payments between seller (95%) and company (5%) by default
- **ERC20 Support**: Works with any ERC20 token
- **Gasless Approvals**: Optional ERC20 permit() support for meta-transactions
- **Secure Claims**: Sellers can securely claim their accumulated balances
- **Configurable**: Owner can adjust fee rates and company wallet

## Key Functions

### `pay()`
Make a payment for a service:
- Specify seller, token, amount
- Include service and invoice IDs for tracking
- Optional permit data for gasless approvals

### `claim()`
Sellers can withdraw their accumulated balances for any token.

### `getSellerInfo()`
View a seller's claimable balance for a specific token.

## Fee Structure
- Default: 95% to seller, 5% to company
- Configurable by owner (up to 10% max company fee)
- Fees calculated in basis points (500 = 5%)

## Events
- `Paid`: Emitted when a payment is processed
- `Claimed`: Emitted when a seller claims funds
- `CommissionUpdated`: Emitted when fee rate changes
- `CompanyWalletUpdated`: Emitted when company wallet changes

## Security
- Ownable contract with restricted admin functions
- Input validation and safe ERC20 transfers
- Maximum fee limit to protect sellers

## Development

### Foundry Commands

```bash
# Initialize new project
forge init

# Install dependencies
forge install openzeppelin/openzeppelin-contracts

# Build contract
forge build

# Run tests
forge test
```