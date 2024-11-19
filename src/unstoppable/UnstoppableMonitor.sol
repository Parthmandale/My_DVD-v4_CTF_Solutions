// SPDX-License-Identifier: MIT
// Damn Vulnerable DeFi v4 (https://damnvulnerabledefi.xyz)
pragma solidity =0.8.25;

import {IERC3156FlashBorrower} from "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";
import {Owned} from "solmate/auth/Owned.sol";
import {UnstoppableVault, ERC20} from "../unstoppable/UnstoppableVault.sol";

/**
 * @notice Permissioned contract for on-chain monitoring of the vault's flashloan feature.
 */
contract UnstoppableMonitor is Owned, IERC3156FlashBorrower {
    UnstoppableVault private immutable vault;

    error UnexpectedFlashLoan();

    event FlashLoanStatus(bool success);

    constructor(address _vault) Owned(msg.sender) {
        vault = UnstoppableVault(_vault);
    }

    function onFlashLoan(address initiator, address token, uint256 amount, uint256 fee, bytes calldata)
        external
        returns (bytes32)
    {
        // initiator must be this contract address itself || vault must be the caller who is calling this function || token must be the same as the vault's asset || fee must be 0
        if (initiator != address(this) || msg.sender != address(vault) || token != address(vault.asset()) || fee != 0) {
            revert UnexpectedFlashLoan();
        }

        // @audit not approving amount+fee to transfer back to vault " altho fee here is 0
        ERC20(token).approve(address(vault), amount);

        return keccak256("IERC3156FlashBorrower.onFlashLoan");
    }

    function checkFlashLoan(uint256 amount) external onlyOwner {
        require(amount > 0);

        address asset = address(vault.asset());

        // try catch istead of doing revert, it emits the logs

        try vault.flashLoan(this, asset, amount, bytes("")) {
            // this emit will only happen if the above func call is successfull and no revert happened, if the revert happened there then instead of reverting this whole tx, it will go in catch block and emit the logs of that and implement the remaining func call.
            emit FlashLoanStatus(true);
        } catch {
            // Something bad happened
            emit FlashLoanStatus(false);

            // Pause the vault
            vault.setPause(true);

            // Transfer ownership to allow review & fixes
            vault.transferOwnership(owner);
        }
    }
}
