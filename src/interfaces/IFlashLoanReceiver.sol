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
    // q is the token, the token being borrowed??
    // @audit-info missing natspec
    // q amount is the amount of tokens?
    // q fee is the fee of the protocol
    // q what is params
    // e whenever a flash loan is taken
    // I think `calldata` will be sent in this `params`
    // calldata will include go to different exchnage, do the arbritarge
    // then return back the flash loan with fee
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
