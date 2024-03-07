// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.20;

// @audit-info this import is only used in `test/mocks/MockFlashLoanReceiver.sol:6:1`
// instead of importing from this interface
// inside the mocks we can directly import `IThunderLoan`
import { IThunderLoan } from "./IThunderLoan.sol";

/**
 * @dev Inspired by Aave:
 * https://github.com/aave/aave-v3-core/blob/master/contracts/flashloan/interfaces/IFlashLoanReceiver.sol
 */
interface IFlashLoanReceiver {
    // qanswered is the token, the token being borrowed??
    // a Yes!
    // @audit-info missing natspec
    // qanswered amount is the amount of tokens? // a Yes!
    // qanswered fee is the fee of the protocol // a Yes!
    // qanswered what is params
    // e whenever a flash loan is taken

    // Note: to call a flash loan
    // we need to setup a smart contract
    // and that smart contract should inherit `IFlashLoanReceiver`
    // whenever flashloan is called, `thunderLoan` contract will execute the `executeOperation` function
    // for the calling contract
    function executeOperation(
        address token,
        uint256 amount,
        uint256 fee,
        address initiator,
        bytes calldata params
    )
        external
        returns (bool);
}
