// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import "./DeltaSetup.f.sol";

contract ForkTestPolygon is DeltaSetup {
    function setUp() public virtual override {
        vm.createSelectFork({blockNumber: 60576649, urlOrAlias: "https://polygon-rpc.com"});
        address admin = 0x999999833d965c275A2C102a4Ebf222ca938546f;
        address proxy = 0x6A6faa54B9238f0F079C8e6CBa08a7b9776C7fE4;
        address oldModule = 0xdbE9Ff7197c0AD8e1Ecc247b803fd739227aC62b;
        upgradeExistingDelta(proxy, admin, oldModule);
    }

    // skipt this one for now
    function test_permit_polygon() external /** address user, uint8 lenderId */ {
        address user = 0x91ae002a960e63Ccb0E5bDE83A8C13E51e1cB91A;
        vm.prank(user);
        // vm.expectRevert(); // should revert with overflow
        IFlashAggregator(brokerProxyAddress).deltaCompose(getSwapWithPermit());
    }

    // skipt this one for now
    function test_generic_polygon() external /** address user, uint8 lenderId */ {
        address user = 0x91ae002a960e63Ccb0E5bDE83A8C13E51e1cB91A;
        vm.prank(user);
        vm.expectRevert(0x7dd37f70); // should revert with slippage
        (bool success, bytes memory ret) = address(brokerProxyAddress).call{value: 5000000000000000000}(abi.encodeWithSelector(IFlashAggregator.deltaCompose.selector, getGenericData()));
        if (!success) {
            console.logBytes(ret);
            // Next 5 lines from https://ethereum.stackexchange.com/a/83577
            if (ret.length < 68) revert();
            assembly {
                ret := add(ret, 0x04)
            }
            revert(abi.decode(ret, (string)));
        }
    }

    function getSwapWithPermit() internal pure returns (bytes memory data) {
        // this data is correct for bloclk 59909525
        data = hex"32f329e36c7bf6e5e86ce2150875a84ce77f47737500e000000000000000000000000091ae002a960e63ccb0e5bde83a8c13e51e1cb91a0000000000000000000000006a6faa54b9238f0f079c8e6cba08a7b9776c7fe40000000000000000000000000000000000000000000000000221405dd9d7791f0000000000000000000000000000000000000000000000000000000066a643f5000000000000000000000000000000000000000000000000000000000000001c6106cedd1eee05901450585ba677ba4f29aaa5953bce23eb679224ba4a363feb38503fdaaf6105b10ebfca6342bb8b9ca775295803cd9d79f37571d74b11ef4034ffd6df932a45c0f255f85145f286ea0b292b21c90b000000000000021bda57da3830f4054204d6df932a45c0f255f85145f286ea0b292b21c90b216b4b4ba9f3e719726886d34a177484278bfcaedef171fe48cf0115b1d80b88dc8eab59176fee57000000000000021bcc8639e810cd04842298207a0000000000000000000000000000000000000000000000000000000000000020000000000000000000000000d6df932a45c0f255f85145f286ea0b292b21c90b0000000000000000000000003c499c542cef5e3811e1192ce70d8cc03d5c3359000000000000000000000000000000000000000000000000021bda57da3830f40000000000000000000000000000000000000000000000000000000000e8855b000000000000000000000000000000000000000000000000021bcc8639e810cd00000000000000000000000000000000000000000000000000000000000001e0000000000000000000000000000000000000000000000000000000000000022000000000000000000000000000000000000000000000000000000000000003a0000000000000000000000000000000000000000000000000000000000000040000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000010000000000000000000000000000000000000000000000000000000000c00000000000000000000000000000000000000000000000000000000000000004400000000000000000000000000000000000000000000000000000000066a68ca346a9c2eccf9c4fa6b4f19394cfc36017000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000e592427a0aece92de3edee1f18e0157c058615640000000000000000000000000000000000000000000000000000000000000144f28c0498000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000000a0000000000000000000000000def171fe48cf0115b1d80b88dc8eab59176fee570000000000000000000000000000000000000000000000000000000066af72c30000000000000000000000000000000000000000000000000000000000e8855b000000000000000000000000000000000000000000000000021bda57da3830f400000000000000000000000000000000000000000000000000000000000000423c499c542cef5e3811e1192ce70d8cc03d5c33590001f453e0bca35ec356bd5dddfebbd1fc0fd03fabad39002710d6df932a45c0f255f85145f286ea0b292b21c90b00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000144000000000000000000000000000000000000000000000000000000000000000100000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000123c499c542cef5e3811e1192ce70d8cc03d5c335991ae002a960e63ccb0e5bde83a8c13e51e1cb91a00020000000000000000000000e8943c13d6df932a45c0f255f85145f286ea0b292b21c90bba12222222228d8ba445958a75a0704d566bf2c800000000000000021bda57da3830f4223c499c542cef5e3811e1192ce70d8cc03d5c335991ae002a960e63ccb0e5bde83a8c13e51e1cb91a00000000000000000000000000000010d6df932a45c0f255f85145f286ea0b292b21c90b91ae002a960e63ccb0e5bde83a8c13e51e1cb91a000000000000000000000000000000";
    }

    function getGenericData() internal pure returns (bytes memory data) {
        // this data is incorrect for block 60576346
        data = hex"230000000000004563918244f400000091ae002a960e63ccb0e5bde83a8c13e51e1cb91a8000000000000000000000000011a3560000000000002629f66e0c53000000420d500b1d8e8ef31e21c99d1db9a6444d3adf12700087380615f37993b5a96adf3d443b6e0ac50a211998270b2791bca1f2de4661ed88a30c99a7a9449aa84174ff090091ae002a960e63ccb0e5bde83a8c13e51e1cb91a800000000000000000000000000199c200000000000003782dace9d9000000420d500b1d8e8ef31e21c99d1db9a6444d3adf12700069019011032a7ac3a87ee885b6c08467ac46ad11cd26fc2791bca1f2de4661ed88a30c99a7a9449aa84174ff090091ae002a960e63ccb0e5bde83a8c13e51e1cb91a80000000000000000000000000099c7600000000000014d1120d7b16000000980d500b1d8e8ef31e21c99d1db9a6444d3adf12700064711b6f6788e4cb0f7034bf02b149118a46e500c226f27ceb23fd6bc0add59e62ac25578270cff1b9f6190078c427ec5934c33e67ccca070ed3f65abf31c64607270b1bfd67037b42cf73acf2047067bd4f2c47d9bfd60096ed9e3f98bbed560e66b89aac922e29d4596a96422791bca1f2de4661ed88a30c99a7a9449aa84174ff090091ae002a960e63ccb0e5bde83a8c13e51e1cb91a800000000000000000000000000199d300000000000003782dace9d9000000420d500b1d8e8ef31e21c99d1db9a6444d3adf12700002934f3f8749164111f0386ece4f4965a687e576d500642791bca1f2de4661ed88a30c99a7a9449aa84174ff090091ae002a960e63ccb0e5bde83a8c13e51e1cb91a80000000000000000000000000019a2900000000000003782dace9d90000006e0d500b1d8e8ef31e21c99d1db9a6444d3adf127000007a7374873de28b06386013da94cbd9b554f6ac6e00648f3cf7ad23cd3cadbd9735aff958023239c6a0630003e7e0eb9f6bcccfe847fdf62a3628319a092f11a2cf432791bca1f2de4661ed88a30c99a7a9449aa84174ff09";
    }
}
