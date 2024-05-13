// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.25;

interface ComptrollerInterface {
    function enterMarkets(address[] calldata vTokens) external returns (uint[] memory);

    function exitMarket(address vToken) external returns (uint);

    function updateDelegate(address delegate, bool allowBorrows) external;
}

contract CommonBNBAddresses {
    // unitroller proxy with comptroller interface
    ComptrollerInterface public comptroller = ComptrollerInterface(0xfD36E2c2a6789Db23113685031d7F16329158384);

    address wNative = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;

    address[] assets = [
        0xfb6115445Bff7b52FeB98650C87f44907E58f802, // AAVE
        0x3EE2200Efb3400fAbB9AacF31297cBdD1d435D47, // ADA
        0x8fF795a6F4D97E7887C79beA79aba5cc76444aDf, // BCH
        0x250632378E573c6Be1AC2f97Fcdf00515d0Aa91B, // BETH
        0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c, // BTCB
        0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56, // BUSD
        0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82, // CAKE
        0x1AF3F329e8BE154074D8769D1FFa4eE058B1DBc3, // DAI
        0xbA2aE424d960c26247Dd6c32edC70B295c744C43, // DOGE
        0x7083609fCE4d1d8Dc0C979AAb8c869Ea2C873402, // DOT
        0x2170Ed0880ac9A755fd29B2688956BD959F933F8, // ETH
        0xc5f0f7b66764F6ec8C8Dff7BA683102295E16409, // FDUSD
        0x0D8Ce2A99Bb6e3B7Db580eD848240e4a0F9aE153, // FIL
        0xF8A0BF9cF54Bb92F17374d9e9A321E6a111a51bD, // LINK
        0x4338665CBB7B2485A8855A139b75D5e34AB0DB94, // LTC
        0x156ab3346823B651294766e23e6Cf87254d68962, // LUNA
        0xCC42724C6683B7E57334c4E856f4c9965ED682bD, // MATIC
        0x47BEAd2563dCBf3bF2c9407fEa4dC236fAbA485A, // SXP
        0xCE7de646e7208a4Ef112cb6ed5038FA6cC6b12e3, // TRX
        0x85EAC5Ac2F758618dFa09bDbe0cf174e7d574D5B, // TRXOLD
        0x40af3827F39D0EAcBF4A168f8D4ee67c121D11c9, // TUSD
        0x14016E85a25aeb13065688cAFB43044C2ef86784, // TUSDOLD
        0xBf5140A22578168FD562DCcF235E5D43A02ce9B1, // UNI
        0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d, // USDC
        0x55d398326f99059fF775485246999027B3197955, // USDT
        0x3d4350cD54aeF9f9b2C29435e0fa809957B3F30a, // UST
        // 0x4BD17003473389A42DAF6a0a729f6Fdb328BbBd7, // VAI
        // 0x5F84ce30DC3cF7909101C69086c50De191895883, // VRT
        0xa2E3356610840701BDf5611a53974510Ae27E2e1, // WBETH
        0x1D2F0da169ceB9fC7B3144628dB156f3F6c60dBE, // XRP
        0xcF6BB5389c92Bdda8a3747Ddb454cB7a64626C63 // XVS
    ];

    address vNative = 0xA07c5b74C9B40447a954e1466938b865b6BBea36; // vBNB

    address USDC = 0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d;
    address vUSDC = 0xecA88125a5ADbe82614ffC12D0DB554E2e2867C8;

    address USDT = 0x55d398326f99059fF775485246999027B3197955;
    address vUSDT = 0xecA88125a5ADbe82614ffC12D0DB554E2e2867C8;

    address[] vTokens = [
        0x26DA28954763B92139ED49283625ceCAf52C6f94, // vAAVE
        0x9A0AF7FDb2065Ce470D72664DE73cAE409dA28Ec, // vADA
        0x5F0388EBc2B94FA8E123F404b79cCF5f40b29176, // vBCH
        0x972207A639CC1B374B893cc33Fa251b55CEB7c07, // vBETH
        0x882C173bC7Ff3b7786CA16dfeD3DFFfb9Ee7847B, // vBTC
        0x95c78222B3D6e262426483D42CfA53685A67Ab9D, // vBUSD
        0x86aC3974e2BD0d60825230fa6F355fF11409df5c, // vCAKE
        0x334b3eCB4DCa3593BCCC3c7EBD1A1C1d1780FBF1, // vDAI
        0xec3422Ef92B2fb59e84c8B02Ba73F1fE84Ed8D71, // vDOGE
        0x1610bc33319e9398de5f57B33a5b184c806aD217, // vDOT
        0xf508fCD89b8bd15579dc79A6827cB4686A3592c8, // vETH
        0xC4eF4229FEc74Ccfe17B2bdeF7715fAC740BA0ba, // vFDUSD
        0xf91d58b5aE142DAcC749f58A49FCBac340Cb0343, // vFIL
        0x650b940a1033B8A1b1873f78730FcFC73ec11f1f, // vLINK
        0x57A5297F2cB2c0AaC9D554660acd6D385Ab50c6B, // vLTC
        0xb91A659E88B51474767CD97EF3196A3e7cEDD2c8, // vLUNA
        0x5c9476FcD6a4F9a3654139721c949c2233bBbBc8, // vMATIC
        0x2fF3d0F6990a40261c66E1ff2017aCBc282EB6d0, // vSXP
        0xC5D3466aA484B040eE977073fcF337f2c00071c1, // vTRX
        0x61eDcFe8Dd6bA3c891CB9bEc2dc7657B3B422E93, // vTRXOLD
        0xBf762cd5991cA1DCdDaC9ae5C638F5B5Dc3Bee6E, // vTUSD
        0x08CEB3F4a7ed3500cA0982bcd0FC7816688084c3, // vTUSDOLD
        0x27FF564707786720C71A2e5c1490A63266683612, // vUNI
        0xecA88125a5ADbe82614ffC12D0DB554E2e2867C8, // vUSDC
        0xfD5840Cd36d94D7229439859C0112a4185BC0255, // vUSDT
        0x78366446547D062f45b4C0f320cDaa6d710D87bb, // vUST
        0x6CFdEc747f37DAf3b87a35a1D9c8AD3063A1A8A0, // vWBETH
        0xB248a295732e0225acd3337607cc01068e3b9c10, // vXRP
        0x151B1e2635A717bcDc836ECd6FbB62B674FE3E1D // vXVS
    ];

    address binance_pegged_asset_owner = 0xF68a4b64162906efF0fF6aE34E2bB1Cd42FEf62d;
}
