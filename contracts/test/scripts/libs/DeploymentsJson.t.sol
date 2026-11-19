// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std-1.17.0/src/Test.sol";

import {DeploymentsJson} from "../../../script/libs/DeploymentsJson.sol";
import {ProtocolAdapterDeployments} from "../../../script/libs/ProtocolAdapterDeployments.sol";
import {RecordedDeployments} from "../../../script/libs/RecordedDeployments.sol";

/// @notice Checks that a reader reads only the records of its own package.
contract DeploymentsJsonTest is Test {
    /// @notice A pa-evm reader that runs in this project resolves its directory to the records of the forwarder.
    function test_read_reverts_if_the_directory_holds_the_records_of_another_package() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                DeploymentsJson.RecordsOfAnotherPackage.selector,
                RecordedDeployments._DIRECTORY,
                ProtocolAdapterDeployments._PACKAGE_NAME,
                RecordedDeployments._PACKAGE_NAME
            )
        );
        DeploymentsJson.read({
            directory: RecordedDeployments._DIRECTORY, packageName: ProtocolAdapterDeployments._PACKAGE_NAME
        });
    }
}
