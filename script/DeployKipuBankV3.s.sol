// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Script.sol";
import "../src/KipuBankV3.sol";

contract DeployKipuBankV3 is Script {
    function run() external {
        vm.startBroadcast();

        // Direcciones en Sepolia
        address factory = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f; // Uniswap V2 Factory mock
        address usdc    = 0xf08A50178dfcDe18524640EA6618a1f965821715; // USDC Sepolia
        address weth    = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9; // WETH Sepolia

        // Parámetros de límites
        uint256 bankCap = 1_000_000 * 10**6;    // 1 M USDC
        uint256 withdrawCap = 10_000 * 10**6;   // 10 k USDC

        // Despliegue del contrato
        KipuBankV3 bank = new KipuBankV3(factory, usdc, weth, bankCap, withdrawCap);

        console.log("Contrato desplegado en:", address(bank));

        vm.stopBroadcast();
    }
}
