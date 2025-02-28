// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import "forge-std/Test.sol";

import {IERC1271} from "@openzeppelin/contracts/interfaces/IERC1271.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {MessageHashUtils} from "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import {EntryPoint} from "account-abstraction/core/EntryPoint.sol";
import {IEntryPoint} from "account-abstraction/interfaces/IEntryPoint.sol";
import {PackedUserOperation} from "account-abstraction/interfaces/PackedUserOperation.sol";

import {UpgradeableBeacon} from "../../contracts/1delta/flash-account//proxy/Beacon.sol";
import {BaseLightAccount} from "../../contracts/1delta/flash-account/common/BaseLightAccount.sol";
import {FlashAccount} from "../../contracts/1delta/flash-account/ethereum/FlashAccount.sol";
import {FlashAccountBase} from "../../contracts/1delta/flash-account/FlashAccountBase.sol";
import {FlashAccountFactory} from "../../contracts/1delta/flash-account/FlashAccountFactory.sol";

contract FlashAccountTest is Test {
    using stdStorage for StdStorage;
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    uint256 public constant EOA_PRIVATE_KEY = 1;
    uint256 public constant BEACON_OWNER_PRIVATE_KEY = 2;
    address payable public constant BENEFICIARY = payable(address(0xbe9ef1c1a2ee));
    bytes32 internal constant _MESSAGE_TYPEHASH = keccak256("LightAccountMessage(bytes message)");
    uint256 public mainnetFork;

    address public eoaAddress;
    address public beaconOwner;
    address public initialAccountImplementation;

    FlashAccount public account;
    FlashAccount public beaconOwnerAccount;
    EntryPoint public entryPoint;
    FlashAccountFactory public factory;

    UpgradeableBeacon public accountBeacon;

    LightSwitch public lightSwitch;
    Owner public contractOwner;

    event SimpleAccountInitialized(IEntryPoint indexed entryPoint, address indexed owner);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Initialized(uint64 version);
    event Upgraded(address indexed implementation);

    function setUp() public {
        eoaAddress = vm.addr(EOA_PRIVATE_KEY);
        beaconOwner = vm.addr(BEACON_OWNER_PRIVATE_KEY);

        entryPoint = new EntryPoint();
        FlashAccount implementation = new FlashAccount(entryPoint);
        initialAccountImplementation = address(implementation);
        accountBeacon = new UpgradeableBeacon(beaconOwner, initialAccountImplementation);
        factory = new FlashAccountFactory(beaconOwner, address(accountBeacon), entryPoint);
        account = FlashAccount(payable(factory.createAccount(eoaAddress, 1)));
        vm.deal(address(account), 1 << 128);
        lightSwitch = new LightSwitch();
        contractOwner = new Owner();
        beaconOwnerAccount = FlashAccount(payable(factory.createAccount(beaconOwner, 1)));
    }

    function testExecuteCanBeCalledByOwner() public {
        vm.prank(eoaAddress);
        account.execute(address(lightSwitch), 0, abi.encodeCall(LightSwitch.turnOn, ()));
        assertTrue(lightSwitch.on());
    }

    function testExecuteWithValueCanBeCalledByOwner() public {
        vm.prank(eoaAddress);
        account.execute(address(lightSwitch), 1 ether, abi.encodeCall(LightSwitch.turnOn, ()));
        assertTrue(lightSwitch.on());
        assertEq(address(lightSwitch).balance, 1 ether);
    }

    function testExecuteCanBeCalledByEntryPointWithExternalOwner() public {
        PackedUserOperation memory op = _getSignedOp(
            abi.encodeCall(BaseLightAccount.execute, (address(lightSwitch), 0, abi.encodeCall(LightSwitch.turnOn, ()))),
            EOA_PRIVATE_KEY
        );
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        entryPoint.handleOps(ops, BENEFICIARY);
        assertTrue(lightSwitch.on());
    }

    function testExecutedCanBeCalledByEntryPointWithContractOwner() public {
        _useContractOwner();
        PackedUserOperation memory op = _getUnsignedOp(
            abi.encodeCall(BaseLightAccount.execute, (address(lightSwitch), 0, abi.encodeCall(LightSwitch.turnOn, ())))
        );
        op.signature = abi.encodePacked(BaseLightAccount.SignatureType.CONTRACT, contractOwner.sign(entryPoint.getUserOpHash(op)));
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        entryPoint.handleOps(ops, BENEFICIARY);
        assertTrue(lightSwitch.on());
    }

    function testRejectsUserOpsWithInvalidSignature() public {
        PackedUserOperation memory op = _getSignedOp(
            abi.encodeCall(BaseLightAccount.execute, (address(lightSwitch), 0, abi.encodeCall(LightSwitch.turnOn, ()))),
            1234
        );
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        vm.expectRevert(abi.encodeWithSelector(IEntryPoint.FailedOp.selector, 0, "AA24 signature error"));
        entryPoint.handleOps(ops, BENEFICIARY);
    }

    function testFuzz_rejectsUserOpsWithInvalidSignatureType(uint8 signatureType) public {
        signatureType = uint8(bound(signatureType, 2, type(uint8).max));

        PackedUserOperation memory op = _getUnsignedOp(
            abi.encodeCall(BaseLightAccount.execute, (address(lightSwitch), 0, abi.encodeCall(LightSwitch.turnOn, ())))
        );
        op.signature = abi.encodePacked(signatureType);
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        vm.expectRevert(
            abi.encodeWithSelector(
                IEntryPoint.FailedOpWithRevert.selector,
                0,
                "AA23 reverted",
                abi.encodePacked(BaseLightAccount.InvalidSignatureType.selector)
            )
        );
        entryPoint.handleOps(ops, BENEFICIARY);
    }

    function testRevertsUserOpsWithMalformedSignature() public {
        PackedUserOperation memory op = _getSignedOp(
            abi.encodeCall(BaseLightAccount.execute, (address(lightSwitch), 0, abi.encodeCall(LightSwitch.turnOn, ()))),
            1234
        );
        op.signature = abi.encodePacked(BaseLightAccount.SignatureType.EOA, hex"aaaa");
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        vm.expectRevert(
            abi.encodeWithSelector(
                IEntryPoint.FailedOpWithRevert.selector,
                0,
                "AA23 reverted",
                abi.encodeWithSelector(ECDSA.ECDSAInvalidSignatureLength.selector, (op.signature.length - 1))
            )
        );
        entryPoint.handleOps(ops, BENEFICIARY);

        op.signature = abi.encodePacked(uint8(3));
        vm.expectRevert(
            abi.encodeWithSelector(
                IEntryPoint.FailedOpWithRevert.selector,
                0,
                "AA23 reverted",
                abi.encodeWithSelector(BaseLightAccount.InvalidSignatureType.selector)
            )
        );
        entryPoint.handleOps(ops, BENEFICIARY);

        op.signature = hex"";
        vm.expectRevert(
            abi.encodeWithSelector(
                IEntryPoint.FailedOpWithRevert.selector,
                0,
                "AA23 reverted",
                abi.encodeWithSelector(BaseLightAccount.InvalidSignatureType.selector)
            )
        );
        entryPoint.handleOps(ops, BENEFICIARY);
    }

    function testExecuteCannotBeCalledByRandos() public {
        vm.expectRevert(abi.encodeWithSelector(BaseLightAccount.NotAuthorized.selector, (address(this))));
        account.execute(address(lightSwitch), 0, abi.encodeCall(LightSwitch.turnOn, ()));
    }

    function testExecuteRevertingCallShouldRevertWithSameData() public {
        Reverter reverter = new Reverter();
        vm.prank(eoaAddress);
        vm.expectRevert("did revert");
        account.execute(address(reverter), 0, abi.encodeCall(Reverter.doRevert, ()));
    }

    function testExecuteBatchCalledByOwner() public {
        vm.prank(eoaAddress);
        address[] memory dest = new address[](1);
        dest[0] = address(lightSwitch);
        bytes[] memory func = new bytes[](1);
        func[0] = abi.encodeCall(LightSwitch.turnOn, ());
        account.executeBatch(dest, func);
        assertTrue(lightSwitch.on());
    }

    function testExecuteBatchFailsForUnevenInputArrays() public {
        vm.prank(eoaAddress);
        address[] memory dest = new address[](2);
        dest[0] = address(lightSwitch);
        dest[1] = address(lightSwitch);
        bytes[] memory func = new bytes[](1);
        func[0] = abi.encodeCall(LightSwitch.turnOn, ());
        vm.expectRevert(BaseLightAccount.ArrayLengthMismatch.selector);
        account.executeBatch(dest, func);
    }

    function testExecuteBatchWithValueCalledByOwner() public {
        vm.prank(eoaAddress);
        address[] memory dest = new address[](1);
        dest[0] = address(lightSwitch);
        uint256[] memory value = new uint256[](1);
        value[0] = uint256(1);
        bytes[] memory func = new bytes[](1);
        func[0] = abi.encodeCall(LightSwitch.turnOn, ());
        account.executeBatch(dest, value, func);
        assertTrue(lightSwitch.on());
        assertEq(address(lightSwitch).balance, 1);
    }

    function testExecuteBatchWithValueFailsForUnevenInputArrays() public {
        vm.prank(eoaAddress);
        address[] memory dest = new address[](1);
        dest[0] = address(lightSwitch);
        uint256[] memory value = new uint256[](2);
        value[0] = uint256(1);
        value[1] = uint256(1 ether);
        bytes[] memory func = new bytes[](1);
        func[0] = abi.encodeCall(LightSwitch.turnOn, ());
        vm.expectRevert(BaseLightAccount.ArrayLengthMismatch.selector);
        account.executeBatch(dest, value, func);
    }

    function testInitialize() public {
        FlashAccountFactory factory = new FlashAccountFactory(address(this), address(accountBeacon), entryPoint);
        vm.expectEmit(true, false, false, false);
        emit Initialized(0);
        account = FlashAccount(payable(factory.createAccount(eoaAddress, 1)));
    }

    function testCannotInitializeWithZeroOwner() public {
        FlashAccountFactory _factory = new FlashAccountFactory(address(this), address(accountBeacon), entryPoint);
        vm.expectRevert(abi.encodeWithSelector(FlashAccountBase.InvalidOwner.selector, (address(0))));
        account = FlashAccount(payable(_factory.createAccount(address(0), 1)));
    }

    function testAddDeposit() public {
        assertEq(account.getDeposit(), 0);
        account.addDeposit{value: 10}();
        assertEq(account.getDeposit(), 10);
        assertEq(account.getDeposit(), entryPoint.balanceOf(address(account)));
    }

    function testWithdrawDepositToCalledByOwner() public {
        account.addDeposit{value: 10}();
        vm.prank(eoaAddress);
        account.withdrawDepositTo(BENEFICIARY, 5);
        assertEq(entryPoint.balanceOf(address(account)), 5);
    }

    function testWithdrawDepositCanBeCalledByEntryPointWithExternalOwner() public {
        account.addDeposit{value: 1 ether}();
        address payable withdrawalAddress = payable(address(1));

        PackedUserOperation memory op = _getSignedOp(abi.encodeCall(BaseLightAccount.withdrawDepositTo, (withdrawalAddress, 5)), EOA_PRIVATE_KEY);
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        entryPoint.handleOps(ops, BENEFICIARY);

        assertEq(withdrawalAddress.balance, 5);
    }

    function testWithdrawDepositCanBeCalledBySelf() public {
        account.addDeposit{value: 1 ether}();
        address payable withdrawalAddress = payable(address(1));

        PackedUserOperation memory op = _getSignedOp(
            abi.encodeCall(
                BaseLightAccount.execute,
                (address(account), 0, abi.encodeCall(BaseLightAccount.withdrawDepositTo, (withdrawalAddress, 5)))
            ),
            EOA_PRIVATE_KEY
        );
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        entryPoint.handleOps(ops, BENEFICIARY);

        assertEq(withdrawalAddress.balance, 5);
    }

    function testWithdrawDepositToCannotBeCalledByRandos() public {
        account.addDeposit{value: 10}();
        vm.expectRevert(abi.encodeWithSelector(BaseLightAccount.NotAuthorized.selector, (address(this))));
        account.withdrawDepositTo(BENEFICIARY, 5);
    }

    function testWithdrawDepositToZeroAddress() public {
        account.addDeposit{value: 10}();
        vm.prank(eoaAddress);
        vm.expectRevert(abi.encodeWithSelector(BaseLightAccount.ZeroAddressNotAllowed.selector));
        account.withdrawDepositTo(payable(address(0)), 5);
    }

    function testOwnerCanTransferOwnership() public {
        address newOwner = address(0x100);
        vm.prank(eoaAddress);
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferred(eoaAddress, newOwner);
        account.transferOwnership(newOwner);
        assertEq(account.owner(), newOwner);
    }

    function testEntryPointCanTransferOwnership() public {
        address newOwner = address(0x100);
        PackedUserOperation memory op = _getSignedOp(abi.encodeCall(FlashAccountBase.transferOwnership, (newOwner)), EOA_PRIVATE_KEY);
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferred(eoaAddress, newOwner);
        entryPoint.handleOps(ops, BENEFICIARY);
        assertEq(account.owner(), newOwner);
    }

    function testSelfCanTransferOwnership() public {
        address newOwner = address(0x100);
        PackedUserOperation memory op = _getSignedOp(
            abi.encodeCall(BaseLightAccount.execute, (address(account), 0, abi.encodeCall(FlashAccountBase.transferOwnership, (newOwner)))),
            EOA_PRIVATE_KEY
        );
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;
        vm.expectEmit(true, true, false, false);
        emit OwnershipTransferred(eoaAddress, newOwner);
        entryPoint.handleOps(ops, BENEFICIARY);
        assertEq(account.owner(), newOwner);
    }

    function testRandosCannotTransferOwnership() public {
        vm.expectRevert(abi.encodeWithSelector(BaseLightAccount.NotAuthorized.selector, (address(this))));
        account.transferOwnership(address(0x100));
    }

    function testCannotTransferOwnershipToCurrentOwner() public {
        vm.prank(eoaAddress);
        vm.expectRevert(abi.encodeWithSelector(FlashAccountBase.InvalidOwner.selector, (eoaAddress)));
        account.transferOwnership(eoaAddress);
    }

    function testCannotTransferOwnershipToZero() public {
        vm.prank(eoaAddress);
        vm.expectRevert(abi.encodeWithSelector(FlashAccountBase.InvalidOwner.selector, (address(0))));
        account.transferOwnership(address(0));
    }

    function testCannotTransferOwnershipToLightContractItself() public {
        vm.prank(eoaAddress);
        vm.expectRevert(abi.encodeWithSelector(FlashAccountBase.InvalidOwner.selector, (address(account))));
        account.transferOwnership(address(account));
    }

    function testEntryPointGetter() public {
        assertEq(address(account.entryPoint()), address(entryPoint));
    }

    function testIsValidSignatureForEoaOwner() public {
        bytes32 message = keccak256("hello world");
        bytes memory signature = abi.encodePacked(BaseLightAccount.SignatureType.EOA, _sign(EOA_PRIVATE_KEY, _getMessageHash(abi.encode(message))));
        assertEq(account.isValidSignature(message, signature), bytes4(keccak256("isValidSignature(bytes32,bytes)")));
    }

    function testIsValidSignatureForContractOwner() public {
        _useContractOwner();
        bytes32 message = keccak256("hello world");
        bytes memory signature = abi.encodePacked(BaseLightAccount.SignatureType.CONTRACT, contractOwner.sign(_getMessageHash(abi.encode(message))));
        assertEq(account.isValidSignature(message, signature), bytes4(keccak256("isValidSignature(bytes32,bytes)")));
    }

    function testIsValidSignatureRejectsInvalid() public {
        bytes32 message = keccak256("hello world");
        bytes memory signature = abi.encodePacked(BaseLightAccount.SignatureType.EOA, _sign(123, _getMessageHash(abi.encode(message))));
        assertEq(account.isValidSignature(message, signature), bytes4(0xffffffff));

        // Invalid length
        signature = abi.encodePacked(BaseLightAccount.SignatureType.EOA, hex"1234567890abcdef1234567890abcdef1234567890abcdef");
        vm.expectRevert(abi.encodeWithSelector(ECDSA.ECDSAInvalidSignatureLength.selector, 24));
        account.isValidSignature(message, signature);

        // 0 length
        signature = abi.encodePacked(BaseLightAccount.SignatureType.EOA, hex"");
        vm.expectRevert(abi.encodeWithSelector(ECDSA.ECDSAInvalidSignatureLength.selector, 0));
        account.isValidSignature(message, signature);

        // Missing SignatureType prefix
        signature = _sign(EOA_PRIVATE_KEY, _getMessageHash(abi.encode(message)));
        vm.expectRevert(abi.encodeWithSelector(BaseLightAccount.InvalidSignatureType.selector));
        account.isValidSignature(message, signature);
    }

    function testBeaconOwnerCanUpgrade() public {
        // Upgrade to a normal FlashAccount with a different entry point.
        IEntryPoint newEntryPoint = IEntryPoint(address(0x2000));
        FlashAccount newImplementation = new FlashAccount(newEntryPoint);

        vm.prank(beaconOwner);
        vm.expectEmit(true, false, false, false);
        emit Upgraded(address(newImplementation));
        accountBeacon.upgradeTo(address(newImplementation));
        FlashAccount upgradedAccount = FlashAccount(payable(account));
        assertEq(address(upgradedAccount.entryPoint()), address(newEntryPoint));
    }

    function testEntryPointCanUpgrade() public {
        // transfer the ownership to beaconOwnerAccount
        vm.prank(beaconOwner);
        accountBeacon.transferOwnership(address(beaconOwnerAccount));

        // Create a new implementation
        IEntryPoint newEntryPoint = IEntryPoint(address(0x2000));
        FlashAccount newImplementation = new FlashAccount(newEntryPoint);

        // Fund the beacon owner account
        vm.deal(address(beaconOwnerAccount), 1 ether);

        // Create userOp to call beacon upgrade
        bytes memory callData = abi.encodeCall(
            BaseLightAccount.execute,
            (address(accountBeacon), 0, abi.encodeCall(UpgradeableBeacon.upgradeTo, (address(newImplementation))))
        );

        // Create and sign the user operation using beaconOwnerAccount as sender
        PackedUserOperation memory op = _getUnsignedOp(callData);
        op.sender = address(beaconOwnerAccount); // Use beaconOwnerAccount as sender
        op.signature = abi.encodePacked(
            BaseLightAccount.SignatureType.EOA,
            _sign(BEACON_OWNER_PRIVATE_KEY, entryPoint.getUserOpHash(op).toEthSignedMessageHash())
        );

        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = op;

        vm.expectEmit(true, false, false, false);
        emit Upgraded(address(newImplementation));
        entryPoint.handleOps(ops, BENEFICIARY);

        assertEq(accountBeacon.implementation(), address(newImplementation), "Beacon implementation not updated");

        // Verify the upgrade was successful
        FlashAccount upgradedAccount = FlashAccount(payable(account));
        assertEq(address(upgradedAccount.entryPoint()), address(newEntryPoint), "Account entryPoint not updated");
    }

    // function testSelfCanUpgrade() public {
    //     // Upgrade to a normal SimpleAccount with a different entry point.
    //     IEntryPoint newEntryPoint = IEntryPoint(address(0x2000));
    //     SimpleAccount newImplementation = new SimpleAccount(newEntryPoint);
    //     PackedUserOperation memory op = _getSignedOp(
    //         abi.encodeCall(
    //             BaseLightAccount.execute,
    //             (
    //                 address(account),
    //                 0,
    //                 abi.encodeCall(
    //                     account.upgradeToAndCall,
    //                     (address(newImplementation), abi.encodeCall(SimpleAccount.initialize, (address(this))))
    //                 )
    //             )
    //         ),
    //         EOA_PRIVATE_KEY
    //     );
    //     PackedUserOperation[] memory ops = new PackedUserOperation[](1);
    //     ops[0] = op;

    //     vm.expectEmit(true, true, false, false);
    //     emit SimpleAccountInitialized(newEntryPoint, address(this));
    //     entryPoint.handleOps(ops, BENEFICIARY);

    //     SimpleAccount upgradedAccount = SimpleAccount(payable(account));
    //     assertEq(address(upgradedAccount.entryPoint()), address(newEntryPoint));
    // }

    function testNonOwnerCannotUpgrade() public {
        // Try to upgrade to a normal FlashAccount with a different entry point.
        IEntryPoint newEntryPoint = IEntryPoint(address(0x2000));
        FlashAccount newImplementation = new FlashAccount(newEntryPoint);
        vm.expectRevert(bytes4(0x82b42900)); // Unauthorized()
        accountBeacon.upgradeTo(address(newImplementation));
    }

    function testStorageSlots() public {
        // No storage at start (slot 0).
        bytes32 storageStart = vm.load(address(account), bytes32(uint256(0)));
        assertEq(storageStart, 0);

        // Instead, storage at the chosen locations.
        bytes32 accountSlot = keccak256("flash_account.storage");
        address owner = abi.decode(abi.encode(vm.load(address(account), accountSlot)), (address));
        assertEq(owner, eoaAddress);

        bytes32 initializableSlot = keccak256("flash_account.initializable");
        uint8 initialized = abi.decode(abi.encode(vm.load(address(account), initializableSlot)), (uint8));
        assertEq(initialized, 1);
    }

    function testRevertCreate_IncorrectCaller() public {
        vm.expectRevert(abi.encodeWithSelector(BaseLightAccount.NotAuthorized.selector, address(this)));
        account.performCreate(0, hex"1234");
    }

    function testRevertCreate_CreateFailed() public {
        vm.prank(eoaAddress);
        vm.expectRevert(BaseLightAccount.CreateFailed.selector);
        account.performCreate(0, hex"3d3dfd");
    }

    function testRevertCreate2_IncorrectCaller() public {
        vm.expectRevert(abi.encodeWithSelector(BaseLightAccount.NotAuthorized.selector, address(this)));
        account.performCreate2(0, hex"1234", bytes32(0));
    }

    function testRevertCreate2_CreateFailed() public {
        vm.prank(eoaAddress);
        vm.expectRevert(BaseLightAccount.CreateFailed.selector);
        account.performCreate2(0, hex"3d3dfd", bytes32(0));
    }

    function testCreate() public {
        address expected = vm.computeCreateAddress(address(account), vm.getNonce(address(account)));

        vm.prank(eoaAddress);
        address returnedAddress = account.performCreate(0, abi.encodePacked(type(FlashAccount).creationCode, abi.encode(address(entryPoint))));
        assertEq(address(FlashAccount(payable(expected)).entryPoint()), address(entryPoint));
        assertEq(returnedAddress, expected);
    }

    function testCreateValue() public {
        vm.prank(eoaAddress);
        address expected = vm.computeCreateAddress(address(account), vm.getNonce(address(account)));

        uint256 value = 1 ether;
        vm.deal(address(account), value);

        address returnedAddress = account.performCreate(value, "");

        assertEq(returnedAddress, expected);
        assertEq(returnedAddress.balance, value);
    }

    function testCreate2() public {
        vm.prank(eoaAddress);

        bytes memory initCode = abi.encodePacked(type(FlashAccount).creationCode, abi.encode(address(entryPoint)));
        bytes32 initCodeHash = keccak256(initCode);
        bytes32 salt = bytes32(hex"04546b");

        address expected = vm.computeCreate2Address(salt, initCodeHash, address(account));

        address returnedAddress = account.performCreate2(0, initCode, salt);

        assertEq(returnedAddress, expected);
        assertEq(address(FlashAccount(payable(returnedAddress)).entryPoint()), address(entryPoint));
    }

    function testCreate2Value() public {
        vm.prank(eoaAddress);
        bytes memory initCode = "";
        bytes32 initCodeHash = keccak256(initCode);
        bytes32 salt = bytes32(hex"04546b");
        address expected = vm.computeCreate2Address(salt, initCodeHash, address(account));

        uint256 value = 1 ether;
        vm.deal(address(account), value);

        address returnedAddress = account.performCreate2(value, initCode, salt);
        assertEq(returnedAddress, expected);
        assertEq(returnedAddress.balance, value);
    }

    function _useContractOwner() internal {
        vm.prank(eoaAddress);
        account.transferOwnership(address(contractOwner));
    }

    function _getUnsignedOp(bytes memory callData) internal view returns (PackedUserOperation memory) {
        uint128 verificationGasLimit = 1 << 24;
        uint128 callGasLimit = 1 << 24;
        uint128 maxPriorityFeePerGas = 1 << 8;
        uint128 maxFeePerGas = 1 << 8;
        return
            PackedUserOperation({
                sender: address(account),
                nonce: 0,
                initCode: "",
                callData: callData,
                accountGasLimits: bytes32((uint256(verificationGasLimit) << 128) | callGasLimit),
                preVerificationGas: 1 << 24,
                gasFees: bytes32((uint256(maxPriorityFeePerGas) << 128) | maxFeePerGas),
                paymasterAndData: "",
                signature: ""
            });
    }

    function _getSignedOp(bytes memory callData, uint256 privateKey) internal view returns (PackedUserOperation memory) {
        PackedUserOperation memory op = _getUnsignedOp(callData);
        op.signature = abi.encodePacked(BaseLightAccount.SignatureType.EOA, _sign(privateKey, entryPoint.getUserOpHash(op).toEthSignedMessageHash()));
        return op;
    }

    function _sign(uint256 privateKey, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }

    /// @dev Purposefully redefined here to surface any necessary updates to client-side message preparation for
    /// signing, in case `account.getMessageHash()` is updated.
    function _getMessageHash(bytes memory message) public view returns (bytes32) {
        bytes32 structHash = keccak256(abi.encode(_MESSAGE_TYPEHASH, keccak256(message)));
        return keccak256(abi.encodePacked("\x19\x01", _domainSeparator(), structHash));
    }

    /// @dev Domain separator for the account.
    function _domainSeparator() internal view returns (bytes32) {
        (, string memory name, string memory version, , , , ) = account.eip712Domain();
        return
            keccak256(
                abi.encode(
                    keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                    keccak256(bytes(name)),
                    keccak256(bytes(version)),
                    block.chainid,
                    address(account)
                )
            );
    }
}

contract LightSwitch {
    bool public on;

    function turnOn() external payable {
        on = true;
    }
}

contract Reverter {
    function doRevert() external pure {
        revert("did revert");
    }
}

contract Owner is IERC1271 {
    function sign(bytes32 digest) public pure returns (bytes memory) {
        return abi.encodePacked("Signed: ", digest);
    }

    function isValidSignature(bytes32 digest, bytes memory signature) public pure override returns (bytes4) {
        if (keccak256(signature) == keccak256(sign(digest))) {
            return bytes4(keccak256("isValidSignature(bytes32,bytes)"));
        }
        return 0xffffffff;
    }
}
