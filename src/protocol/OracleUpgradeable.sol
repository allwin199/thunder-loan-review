// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import { ITSwapPool } from "../interfaces/ITSwapPool.sol";
import { IPoolFactory } from "../interfaces/IPoolFactory.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract OracleUpgradeable is Initializable {
    address private s_poolFactory;

    // upgradeable contract can't have constructors
    // why can't they have constructors?
    // because `storage` is in `proxy`
    // `logic` is in `implementation`
    // if we have a constructor in a implementation contract and have some storage in it
    // it will not matter, because `storage` is in `proxy`

    // When user makes a call to the proxy contract
    // `proxy` routes it to the `implementation` contract, if the function selector dosen't match
    // but `storage` will be in the `proxy` contract

    // Therfore `initializable` contract helps proxies initialize with storage

    function __Oracle_init(address poolFactoryAddress) internal onlyInitializing {
        __Oracle_init_unchained(poolFactoryAddress);
    }

    function __Oracle_init_unchained(address poolFactoryAddress) internal onlyInitializing {
        s_poolFactory = poolFactoryAddress;

        // above setup is to
        // `initialize` the upgradeable smart contract
        // `initialize` the storage correctly
    }

    // e omg we are calling an external contract
    // what is the price is manipulated
    // can I manipulate the price
    // re-entrancy???
    // how this external call been tested
    // are they using forked test or just using mocks
    // they are testing using mocks
    // @audit-info you should use forked test for this
    function getPriceInWeth(address token) public view returns (uint256) {
        address swapPoolOfToken = IPoolFactory(s_poolFactory).getPool(token);
        return ITSwapPool(swapPoolOfToken).getPriceOfOnePoolTokenInWeth();
    }

    function getPrice(address token) external view returns (uint256) {
        return getPriceInWeth(token);
    }

    function getPoolFactoryAddress() external view returns (address) {
        return s_poolFactory;
    }
}
