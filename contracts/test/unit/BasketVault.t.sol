// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {BasketVault} from "../../src/vault/BasketVault.sol";
import {KandaToken} from "../../src/token/KandaToken.sol";
import {ParticipantRegistry} from "../../src/registry/ParticipantRegistry.sol";
import {IBasketVault} from "../../src/interfaces/IBasketVault.sol";
import {IKandaToken} from "../../src/interfaces/IKandaToken.sol";
import {IParticipantRegistry} from "../../src/interfaces/IParticipantRegistry.sol";
import {Roles} from "../../src/governance/Roles.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {MockGoldToken} from "../mocks/MockGoldToken.sol";
import {BasketVaultV2Mock} from "../mocks/BasketVaultV2Mock.sol";

/// @notice Shared setup: KND, registry and vault proxies wired as WireRoles will wire them, with the P1 basket
///         (0.70 USDC + G oz DGLD per KND, L1 section 4), cap and fee.
abstract contract BasketVaultTestBase is Test {
    uint256 internal constant USDC_QTY = 700_000; // 0.70 USDC (6 decimals) per 1e18 KND
    uint256 internal constant GOLD_QTY = 70_000_000_000_000; // 0.00007 oz DGLD (18 decimals) per 1e18 KND
    uint256 internal constant SUPPLY_CAP = 1_000_000e18;
    uint16 internal constant FEE_BPS = 10;
    uint128 internal constant TIER1_LIMIT = 50_000e18;

    KandaToken internal knd;
    ParticipantRegistry internal registry;
    BasketVault internal vault;
    BasketVault internal implementation;
    MockERC20 internal usdc;
    MockGoldToken internal gold;

    address internal admin = makeAddr("admin");
    address internal limitsAdmin = makeAddr("limitsAdmin");
    address internal pauser = makeAddr("pauser");
    address internal unpauser = makeAddr("unpauser");
    address internal compliance = makeAddr("compliance");
    address internal upgrader = makeAddr("upgrader");
    address internal feeRecipient = makeAddr("feeRecipient");
    address internal ap = makeAddr("authorizedParticipant");
    address internal partner = makeAddr("partner");
    address internal holder = makeAddr("holder");
    address internal stranger = makeAddr("stranger");

    function setUp() public virtual {
        usdc = new MockERC20("USD Coin", "USDC", 6);
        gold = new MockGoldToken();
        _deploy(_defaultLegs());
    }

    function _defaultLegs() internal view returns (IBasketVault.Leg[] memory legs) {
        legs = new IBasketVault.Leg[](2);
        legs[0] = IBasketVault.Leg(address(usdc), USDC_QTY);
        legs[1] = IBasketVault.Leg(address(gold), GOLD_QTY);
    }

    function _deploy(IBasketVault.Leg[] memory legs) internal {
        knd = KandaToken(
            address(new ERC1967Proxy(address(new KandaToken()), abi.encodeCall(KandaToken.initialize, (admin))))
        );
        registry = ParticipantRegistry(
            address(
                new ERC1967Proxy(
                    address(new ParticipantRegistry()), abi.encodeCall(ParticipantRegistry.initialize, (admin))
                )
            )
        );
        implementation = new BasketVault();
        vault = BasketVault(
            address(new ERC1967Proxy(address(implementation), _initCall(legs, SUPPLY_CAP, FEE_BPS, feeRecipient)))
        );

        vm.startPrank(admin);
        knd.grantRole(Roles.MINTER_ROLE, address(vault));
        knd.grantRole(Roles.COMPLIANCE_ROLE, compliance);
        knd.grantRole(Roles.PAUSER_ROLE, pauser);
        registry.grantRole(Roles.LIMITS_CONSUMER_ROLE, address(vault));
        registry.grantRole(Roles.LIMITS_ADMIN_ROLE, limitsAdmin);
        registry.grantRole(Roles.PARTICIPANT_MANAGER_ROLE, admin);
        vault.grantRole(Roles.LIMITS_ADMIN_ROLE, limitsAdmin);
        vault.grantRole(Roles.PAUSER_ROLE, pauser);
        vault.grantRole(Roles.UNPAUSER_ROLE, unpauser);
        vault.grantRole(Roles.UPGRADER_ROLE, upgrader);
        vm.stopPrank();

        vm.prank(limitsAdmin);
        registry.setTier(1, IParticipantRegistry.TierLimits(TIER1_LIMIT, TIER1_LIMIT));
        vm.startPrank(admin);
        registry.setAccount(ap, IParticipantRegistry.Kind.Participant, 1, true);
        registry.setAccount(partner, IParticipantRegistry.Kind.Partner, 1, true);
        vm.stopPrank();

        _fund(ap);
    }

    function _initCall(IBasketVault.Leg[] memory legs, uint256 cap, uint16 feeBps, address recipient)
        internal
        view
        returns (bytes memory)
    {
        return abi.encodeCall(
            BasketVault.initialize, (admin, address(knd), address(registry), legs, cap, feeBps, recipient)
        );
    }

    function _fund(address account) internal {
        (, IBasketVault.Leg[] memory legs) = vault.legs();
        vm.startPrank(account);
        for (uint256 i; i < legs.length; ++i) {
            // 1e30 base units covers any fuzzed amount on either decimals.
            if (legs[i].asset == address(gold)) gold.mint(account, 1e30);
            else MockERC20(legs[i].asset).mint(account, 1e30);
            IERC20(legs[i].asset).approve(address(vault), type(uint256).max);
        }
        knd.approve(address(vault), type(uint256).max);
        vm.stopPrank();
    }

    function _create(uint256 kndAmount) internal returns (uint256) {
        vm.prank(ap);
        return vault.createInKind(kndAmount, 0, ap);
    }

    function _redeem(uint256 kndAmount) internal returns (uint256[] memory) {
        vm.prank(ap);
        return vault.redeemInKind(kndAmount, new uint256[](2), ap);
    }

    /// @dev INV-1: for every leg, balanceOf(vault) >= ceil(totalSupply * qtyPerUnit / 1e18).
    function _assertBacked() internal view {
        (, IBasketVault.Leg[] memory legs) = vault.legs();
        uint256 supply = knd.totalSupply();
        for (uint256 i; i < legs.length; ++i) {
            uint256 required = Math.mulDiv(supply, legs[i].qtyPerUnit, 1e18, Math.Rounding.Ceil);
            assertGe(IERC20(legs[i].asset).balanceOf(address(vault)), required, "INV-1");
        }
    }

    function _feeOf(uint256 amount) internal pure returns (uint256) {
        return Math.mulDiv(amount, FEE_BPS, 10_000, Math.Rounding.Ceil);
    }

    function _expectMissingRole(address account, bytes32 role) internal {
        vm.expectRevert(abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, account, role));
    }
}

/// @notice Unit tests for BasketVault, L1 section 3.3: create and redeem in the specified order, rounding against
///         the user, fee-on-transfer gold, the supply cap, both pauses, and every role and revert.
contract BasketVaultTest is BasketVaultTestBase {
    // =============================================================
    // Initialization
    // =============================================================

    function test_initialize_setsGenesisBasket() public view {
        (uint32 version, IBasketVault.Leg[] memory legs) = vault.legs();
        assertEq(version, 1);
        assertEq(legs.length, 2);
        assertEq(legs[0].asset, address(usdc));
        assertEq(legs[0].qtyPerUnit, USDC_QTY);
        assertEq(legs[1].asset, address(gold));
        assertEq(legs[1].qtyPerUnit, GOLD_QTY);
        assertFalse(vault.paused());
        assertFalse(vault.createPaused());
    }

    function test_initialize_emitsGenesisEvents() public {
        IBasketVault.Leg[] memory legs = _defaultLegs();
        vm.expectEmit();
        emit IBasketVault.BasketVersionSet(1, legs);
        vm.expectEmit();
        emit IBasketVault.SupplyCapSet(SUPPLY_CAP);
        vm.expectEmit();
        emit IBasketVault.FeeSet(FEE_BPS, feeRecipient);
        new ERC1967Proxy(address(implementation), _initCall(legs, SUPPLY_CAP, FEE_BPS, feeRecipient));
    }

    function test_initialize_grantsOnlyDefaultAdmin() public {
        BasketVault fresh = BasketVault(
            address(new ERC1967Proxy(address(implementation), _initCall(_defaultLegs(), SUPPLY_CAP, 0, feeRecipient)))
        );
        assertTrue(fresh.hasRole(fresh.DEFAULT_ADMIN_ROLE(), admin));
        assertFalse(fresh.hasRole(Roles.LIMITS_ADMIN_ROLE, admin));
        assertFalse(fresh.hasRole(Roles.PAUSER_ROLE, admin));
        assertFalse(fresh.hasRole(Roles.UNPAUSER_ROLE, admin));
        assertFalse(fresh.hasRole(Roles.UPGRADER_ROLE, admin));
    }

    function test_initialize_revertsOnZeroAddresses() public {
        IBasketVault.Leg[] memory legs = _defaultLegs();
        bytes[4] memory calls = [
            abi.encodeCall(
                BasketVault.initialize,
                (address(0), address(knd), address(registry), legs, SUPPLY_CAP, FEE_BPS, feeRecipient)
            ),
            abi.encodeCall(
                BasketVault.initialize, (admin, address(0), address(registry), legs, SUPPLY_CAP, FEE_BPS, feeRecipient)
            ),
            abi.encodeCall(
                BasketVault.initialize, (admin, address(knd), address(0), legs, SUPPLY_CAP, FEE_BPS, feeRecipient)
            ),
            abi.encodeCall(
                BasketVault.initialize, (admin, address(knd), address(registry), legs, SUPPLY_CAP, FEE_BPS, address(0))
            )
        ];
        for (uint256 i; i < calls.length; ++i) {
            vm.expectRevert(IBasketVault.ZeroAddress.selector);
            new ERC1967Proxy(address(implementation), calls[i]);
        }
    }

    function test_initialize_revertsOnFeeTooHigh() public {
        vm.expectRevert(abi.encodeWithSelector(IBasketVault.FeeTooHigh.selector, 101));
        new ERC1967Proxy(address(implementation), _initCall(_defaultLegs(), SUPPLY_CAP, 101, feeRecipient));
    }

    function test_initialize_revertsOnEmptyBasket() public {
        vm.expectRevert(IBasketVault.InvalidBasket.selector);
        new ERC1967Proxy(
            address(implementation), _initCall(new IBasketVault.Leg[](0), SUPPLY_CAP, FEE_BPS, feeRecipient)
        );
    }

    function test_initialize_revertsOnZeroAsset() public {
        IBasketVault.Leg[] memory legs = _defaultLegs();
        legs[1].asset = address(0);
        vm.expectRevert(IBasketVault.InvalidBasket.selector);
        new ERC1967Proxy(address(implementation), _initCall(legs, SUPPLY_CAP, FEE_BPS, feeRecipient));
    }

    function test_initialize_revertsOnRepeatedAsset() public {
        IBasketVault.Leg[] memory legs = _defaultLegs();
        legs[1].asset = address(usdc);
        vm.expectRevert(IBasketVault.InvalidBasket.selector);
        new ERC1967Proxy(address(implementation), _initCall(legs, SUPPLY_CAP, FEE_BPS, feeRecipient));
    }

    function test_initialize_revertsOnZeroQuantity() public {
        IBasketVault.Leg[] memory legs = _defaultLegs();
        legs[0].qtyPerUnit = 0;
        vm.expectRevert(IBasketVault.InvalidBasket.selector);
        new ERC1967Proxy(address(implementation), _initCall(legs, SUPPLY_CAP, FEE_BPS, feeRecipient));
    }

    function test_initialize_revertsWhenCalledTwice() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        vault.initialize(admin, address(knd), address(registry), _defaultLegs(), SUPPLY_CAP, FEE_BPS, feeRecipient);
    }

    function test_implementation_initializersDisabled() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        implementation.initialize(
            admin, address(knd), address(registry), _defaultLegs(), SUPPLY_CAP, FEE_BPS, feeRecipient
        );
    }

    // =============================================================
    // createInKind
    // =============================================================

    function test_create_pullsBasketAndMintsNetAndFee() public {
        uint256 amount = 1000e18;
        uint256 fee = _feeOf(amount); // 1e18
        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[0] = 700e6;
        amountsIn[1] = 0.07e18;

        vm.expectEmit(address(vault));
        emit IBasketVault.Created(ap, holder, amount, fee, amountsIn);
        vm.prank(ap);
        uint256 out = vault.createInKind(amount, amount - fee, holder);

        assertEq(out, amount - fee);
        assertEq(knd.balanceOf(holder), amount - fee);
        assertEq(knd.balanceOf(feeRecipient), fee);
        assertEq(knd.totalSupply(), amount);
        assertEq(usdc.balanceOf(address(vault)), 700e6);
        assertEq(gold.balanceOf(address(vault)), 0.07e18);
        (uint256 createLeft,) = registry.remaining(ap);
        assertEq(createLeft, TIER1_LIMIT - amount);
        _assertBacked();
    }

    function test_create_pullsRoundedUp() public {
        // 1 base unit of KND needs 0.0000007 USDC base units: the vault pulls 1 (rounded up, against the user).
        _create(1);
        assertEq(usdc.balanceOf(address(vault)), 1);
        assertEq(gold.balanceOf(address(vault)), 1);
        assertEq(knd.totalSupply(), 1);
        // The fee also rounds up: 1 unit of fee on 1 unit gross, so the net is zero.
        assertEq(knd.balanceOf(feeRecipient), 1);
        assertEq(knd.balanceOf(ap), 0);
        _assertBacked();
    }

    function test_create_feeOnTransferGold_scarcestLegDecides() public {
        gold.setTransferFeeBps(100); // 1% of gold lost in transfer
        uint256 amount = 1000e18;

        uint256 out = _create(amount);

        uint256 goldReceived = 0.07e18 - 0.0007e18;
        uint256 gross = goldReceived * 1e18 / GOLD_QTY; // 990e18
        assertEq(gross, 990e18);
        assertEq(knd.totalSupply(), gross);
        assertEq(out, gross - _feeOf(gross));
        // USDC for the full 1,000 was pulled; the extra 7 USDC stays as surplus backing.
        assertEq(usdc.balanceOf(address(vault)), 700e6);
        assertGt(vault.coverage()[0], 10_000);
        _assertBacked();
    }

    function test_create_feeOnTransfer_emitsReceivedAmounts() public {
        gold.setTransferFeeBps(100);
        uint256[] memory amountsIn = new uint256[](2);
        amountsIn[0] = 700e6;
        amountsIn[1] = 0.0693e18;
        vm.expectEmit(address(vault));
        emit IBasketVault.Created(ap, ap, 990e18, _feeOf(990e18), amountsIn);
        _create(1000e18);
    }

    function test_create_revertsBelowMinOut() public {
        uint256 amount = 1000e18;
        uint256 net = amount - _feeOf(amount);
        vm.expectRevert(abi.encodeWithSelector(IBasketVault.MintBelowMin.selector, net, net + 1));
        vm.prank(ap);
        vault.createInKind(amount, net + 1, ap);
    }

    function test_create_minOutProtectsAgainstFeeOnTransfer() public {
        gold.setTransferFeeBps(100);
        uint256 amount = 1000e18;
        uint256 expectedNet = amount - _feeOf(amount);
        uint256 net = 990e18 - _feeOf(990e18);
        vm.expectRevert(abi.encodeWithSelector(IBasketVault.MintBelowMin.selector, net, expectedNet));
        vm.prank(ap);
        vault.createInKind(amount, expectedNet, ap);
    }

    function test_create_upToCapExactly() public {
        vm.prank(limitsAdmin);
        vault.setSupplyCap(1000e18);
        _create(1000e18);
        assertEq(knd.totalSupply(), 1000e18);
    }

    function test_create_revertsAboveCap() public {
        vm.prank(limitsAdmin);
        vault.setSupplyCap(1000e18);
        _create(600e18);
        vm.expectRevert(abi.encodeWithSelector(IBasketVault.SupplyCapExceeded.selector, 1000e18 + 1, 1000e18));
        _create(400e18 + 1);
    }

    function test_create_revertsOnZeroAmount() public {
        vm.expectRevert(IBasketVault.ZeroAmount.selector);
        _create(0);
    }

    function test_create_revertsOnZeroRecipient() public {
        vm.expectRevert(IBasketVault.ZeroAddress.selector);
        vm.prank(ap);
        vault.createInKind(1e18, 0, address(0));
    }

    function test_create_revertsOnBlockedRecipient() public {
        vm.prank(compliance);
        knd.blockAccount(holder);
        vm.expectRevert(abi.encodeWithSelector(IKandaToken.AccountBlocked.selector, holder));
        vm.prank(ap);
        vault.createInKind(1e18, 0, holder);
    }

    function test_create_revertsForNonParticipant() public {
        _fund(stranger);
        vm.expectRevert(abi.encodeWithSelector(IParticipantRegistry.NotActive.selector, stranger));
        vm.prank(stranger);
        vault.createInKind(1e18, 0, stranger);
    }

    function test_create_revertsForPartnerOnly() public {
        _fund(partner);
        vm.expectRevert(abi.encodeWithSelector(IParticipantRegistry.NotActive.selector, partner));
        vm.prank(partner);
        vault.createInKind(1e18, 0, partner);
    }

    function test_create_revertsOverDailyLimit() public {
        _create(TIER1_LIMIT);
        vm.expectRevert(abi.encodeWithSelector(IParticipantRegistry.LimitExceeded.selector, ap, 1e18, 0));
        _create(1e18);
    }

    function test_create_revertsWhenVaultPaused() public {
        vm.prank(pauser);
        vault.pause();
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        _create(1e18);
    }

    function test_create_revertsWhenCreationPaused() public {
        vm.prank(pauser);
        vault.pauseCreate();
        vm.expectRevert(IBasketVault.CreationPaused.selector);
        _create(1e18);
    }

    function test_create_revertsWhenTokenPaused() public {
        vm.prank(pauser);
        knd.pause();
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        _create(1e18);
    }

    function test_create_revertsWhenGoldPaused() public {
        gold.setPaused(true);
        vm.expectRevert(MockGoldToken.TokenPaused.selector);
        _create(1e18);
    }

    function test_create_revertsWhenVaultBlacklistedOnGold() public {
        gold.setBlacklisted(address(vault), true);
        vm.expectRevert(abi.encodeWithSelector(MockGoldToken.AddressBlacklisted.selector, address(vault)));
        _create(1e18);
    }

    function test_create_revertsWithoutApproval() public {
        vm.prank(ap);
        usdc.approve(address(vault), 0);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(vault), 0, 700_000)
        );
        _create(1e18);
    }

    function test_create_zeroFeeMintsNothingToRecipient() public {
        vm.prank(limitsAdmin);
        vault.setFee(0, feeRecipient);
        uint256 out = _create(1000e18);
        assertEq(out, 1000e18);
        assertEq(knd.balanceOf(feeRecipient), 0);
    }

    /// @dev Review C-14: a blocked fee recipient stops create and redeem. The recipient is the treasury Safe.
    function test_create_revertsWhenFeeRecipientBlocked() public {
        vm.prank(compliance);
        knd.blockAccount(feeRecipient);
        vm.expectRevert(abi.encodeWithSelector(IKandaToken.AccountBlocked.selector, feeRecipient));
        _create(1000e18);
    }

    // =============================================================
    // redeemInKind
    // =============================================================

    function test_redeem_burnsNetAndPaysBasket() public {
        _create(1000e18); // ap holds 999e18, feeRecipient 1e18
        uint256 amount = 500e18;
        uint256 fee = _feeOf(amount); // 0.5e18
        uint256 net = amount - fee;
        uint256[] memory expected = new uint256[](2);
        expected[0] = net * USDC_QTY / 1e18;
        expected[1] = net * GOLD_QTY / 1e18;

        uint256 usdcBefore = usdc.balanceOf(holder);
        vm.expectEmit(address(vault));
        emit IBasketVault.Redeemed(ap, holder, amount, fee, expected);
        vm.prank(ap);
        uint256[] memory out = vault.redeemInKind(amount, expected, holder);

        assertEq(out[0], expected[0]);
        assertEq(out[1], expected[1]);
        assertEq(usdc.balanceOf(holder) - usdcBefore, expected[0]);
        assertEq(gold.balanceOf(holder), expected[1]);
        assertEq(knd.balanceOf(ap), 999e18 - amount);
        assertEq(knd.balanceOf(feeRecipient), 1e18 + fee);
        assertEq(knd.totalSupply(), 1000e18 - net);
        assertEq(knd.balanceOf(address(vault)), 0);
        (, uint256 redeemLeft) = registry.remaining(ap);
        assertEq(redeemLeft, TIER1_LIMIT - amount);
        _assertBacked();
    }

    function test_redeem_paysRoundedDownAndFeeRoundsUp() public {
        _create(10e18);
        // 1,999 base units gross: fee ceil(1.999) = 2, net 1,997; USDC floor(1,997 * 0.7e-12) = 0.
        uint256[] memory out = _redeem(1999);
        assertEq(out[0], 0);
        assertEq(out[1], 1997 * GOLD_QTY / 1e18);
        assertEq(knd.balanceOf(feeRecipient), _feeOf(10e18) + 2);
        _assertBacked();
    }

    function test_redeem_worksWhileCreationPaused() public {
        _create(100e18);
        vm.prank(pauser);
        vault.pauseCreate();
        _redeem(50e18);
        _assertBacked();
    }

    function test_redeem_revertsWhenVaultPaused() public {
        _create(100e18);
        vm.prank(pauser);
        vault.pause();
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        _redeem(50e18);
    }

    function test_redeem_revertsWhenTokenPaused() public {
        _create(100e18);
        vm.prank(pauser);
        knd.pause();
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        _redeem(50e18);
    }

    function test_redeem_revertsOnLengthMismatch() public {
        _create(100e18);
        vm.expectRevert(abi.encodeWithSelector(IBasketVault.LengthMismatch.selector, 2, 1));
        vm.prank(ap);
        vault.redeemInKind(50e18, new uint256[](1), ap);
    }

    function test_redeem_revertsOnSlippage() public {
        _create(100e18);
        uint256[] memory preview = vault.previewRedeem(50e18);
        uint256[] memory mins = new uint256[](2);
        mins[0] = preview[0];
        mins[1] = preview[1] + 1;
        vm.expectRevert(abi.encodeWithSelector(IBasketVault.SlippageOut.selector, 1, preview[1], preview[1] + 1));
        vm.prank(ap);
        vault.redeemInKind(50e18, mins, ap);
    }

    function test_redeem_revertsOnZeroAmount() public {
        vm.expectRevert(IBasketVault.ZeroAmount.selector);
        _redeem(0);
    }

    function test_redeem_revertsOnZeroRecipient() public {
        _create(100e18);
        vm.expectRevert(IBasketVault.ZeroAddress.selector);
        vm.prank(ap);
        vault.redeemInKind(1e18, new uint256[](2), address(0));
    }

    function test_redeem_revertsForNonParticipant() public {
        _create(100e18);
        vm.prank(ap);
        knd.transfer(stranger, 10e18);
        vm.expectRevert(abi.encodeWithSelector(IParticipantRegistry.NotActive.selector, stranger));
        vm.prank(stranger);
        vault.redeemInKind(10e18, new uint256[](2), stranger);
    }

    function test_redeem_revertsOverDailyLimit() public {
        _create(TIER1_LIMIT);
        vm.warp(block.timestamp + 1 days);
        _create(TIER1_LIMIT);
        _redeem(TIER1_LIMIT);
        vm.expectRevert(abi.encodeWithSelector(IParticipantRegistry.LimitExceeded.selector, ap, 1e18, 0));
        _redeem(1e18);
    }

    function test_redeem_revertsWithoutApproval() public {
        _create(100e18);
        vm.prank(ap);
        knd.approve(address(vault), 0);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, address(vault), 0, 10e18)
        );
        _redeem(10e18);
    }

    function test_redeem_revertsWhenCallerBlocked() public {
        _create(100e18);
        vm.prank(compliance);
        knd.blockAccount(ap);
        vm.expectRevert(abi.encodeWithSelector(IKandaToken.AccountBlocked.selector, ap));
        _redeem(10e18);
    }

    function test_redeem_revertsWhenVaultBlacklistedOnGold() public {
        _create(100e18);
        gold.setBlacklisted(address(vault), true);
        vm.expectRevert(abi.encodeWithSelector(MockGoldToken.AddressBlacklisted.selector, address(vault)));
        _redeem(10e18);
    }

    function test_redeem_zeroFeeBurnsAll() public {
        _create(100e18);
        vm.prank(limitsAdmin);
        vault.setFee(0, feeRecipient);
        uint256 feeBefore = knd.balanceOf(feeRecipient);
        _redeem(10e18);
        assertEq(knd.balanceOf(feeRecipient), feeBefore);
        assertEq(knd.totalSupply(), 90e18);
    }

    function test_createThenRedeemEverything_leavesSurplusOnly() public {
        _create(1000e18);
        _redeem(knd.balanceOf(ap));
        uint256 fees = knd.balanceOf(feeRecipient);
        vm.prank(feeRecipient);
        knd.transfer(ap, fees);
        _redeem(knd.balanceOf(ap));
        _assertBacked();
        // Rounding kept a sliver of each leg in the vault, never a deficit.
        assertGe(usdc.balanceOf(address(vault)), Math.mulDiv(knd.totalSupply(), USDC_QTY, 1e18, Math.Rounding.Ceil));
    }

    // =============================================================
    // Views
    // =============================================================

    function test_previewCreate_matchesCreate() public {
        (uint256[] memory amountsIn, uint256 net) = vault.previewCreate(1234.5e18);
        uint256 out = _create(1234.5e18);
        assertEq(out, net);
        assertEq(amountsIn[0], usdc.balanceOf(address(vault)));
        assertEq(amountsIn[1], gold.balanceOf(address(vault)));
    }

    function test_previewRedeem_matchesRedeem() public {
        _create(1000e18);
        uint256[] memory preview = vault.previewRedeem(333.3e18);
        uint256[] memory out = _redeem(333.3e18);
        assertEq(out[0], preview[0]);
        assertEq(out[1], preview[1]);
    }

    function test_coverage_maxWhenNoSupply() public view {
        uint256[] memory ratios = vault.coverage();
        assertEq(ratios.length, 2);
        assertEq(ratios[0], type(uint256).max);
        assertEq(ratios[1], type(uint256).max);
    }

    function test_coverage_fullAfterCreate() public {
        _create(1000e18);
        uint256[] memory ratios = vault.coverage();
        assertEq(ratios[0], 10_000);
        assertEq(ratios[1], 10_000);
    }

    function test_coverage_countsDonations() public {
        _create(1000e18);
        usdc.mint(address(vault), 70e6); // +10% of the USDC leg
        assertEq(vault.coverage()[0], 11_000);
    }

    // =============================================================
    // Administration
    // =============================================================

    function test_setSupplyCap_setsAndEmits() public {
        vm.expectEmit(address(vault));
        emit IBasketVault.SupplyCapSet(5e18);
        vm.prank(limitsAdmin);
        vault.setSupplyCap(5e18);
        vm.expectRevert(abi.encodeWithSelector(IBasketVault.SupplyCapExceeded.selector, 6e18, 5e18));
        _create(6e18);
    }

    function test_setSupplyCap_belowSupplyStopsCreateButNotRedeem() public {
        _create(100e18);
        vm.prank(limitsAdmin);
        vault.setSupplyCap(0);
        vm.expectRevert(abi.encodeWithSelector(IBasketVault.SupplyCapExceeded.selector, 101e18, 0));
        _create(1e18);
        _redeem(10e18);
    }

    function test_setSupplyCap_revertsWithoutLimitsAdminRole() public {
        _expectMissingRole(admin, Roles.LIMITS_ADMIN_ROLE);
        vm.prank(admin);
        vault.setSupplyCap(1);
    }

    function test_setFee_setsAndEmits() public {
        vm.expectEmit(address(vault));
        emit IBasketVault.FeeSet(100, stranger);
        vm.prank(limitsAdmin);
        vault.setFee(100, stranger);
        _create(1000e18);
        assertEq(knd.balanceOf(stranger), 10e18);
    }

    function test_setFee_revertsAbove100Bps() public {
        vm.expectRevert(abi.encodeWithSelector(IBasketVault.FeeTooHigh.selector, 101));
        vm.prank(limitsAdmin);
        vault.setFee(101, feeRecipient);
    }

    function test_setFee_revertsOnZeroRecipient() public {
        vm.expectRevert(IBasketVault.ZeroAddress.selector);
        vm.prank(limitsAdmin);
        vault.setFee(10, address(0));
    }

    function test_setFee_revertsWithoutLimitsAdminRole() public {
        _expectMissingRole(pauser, Roles.LIMITS_ADMIN_ROLE);
        vm.prank(pauser);
        vault.setFee(10, feeRecipient);
    }

    function test_pause_roles() public {
        _expectMissingRole(unpauser, Roles.PAUSER_ROLE);
        vm.prank(unpauser);
        vault.pause();

        vm.expectEmit(address(vault));
        emit PausableUpgradeable.Paused(pauser);
        vm.prank(pauser);
        vault.pause();
        assertTrue(vault.paused());

        _expectMissingRole(pauser, Roles.UNPAUSER_ROLE);
        vm.prank(pauser);
        vault.unpause();

        vm.expectEmit(address(vault));
        emit PausableUpgradeable.Unpaused(unpauser);
        vm.prank(unpauser);
        vault.unpause();
        assertFalse(vault.paused());
    }

    function test_pauseCreate_roles() public {
        _expectMissingRole(unpauser, Roles.PAUSER_ROLE);
        vm.prank(unpauser);
        vault.pauseCreate();

        vm.expectEmit(address(vault));
        emit IBasketVault.CreatePaused(pauser);
        vm.prank(pauser);
        vault.pauseCreate();
        assertTrue(vault.createPaused());

        _expectMissingRole(pauser, Roles.UNPAUSER_ROLE);
        vm.prank(pauser);
        vault.unpauseCreate();

        vm.expectEmit(address(vault));
        emit IBasketVault.CreateUnpaused(unpauser);
        vm.prank(unpauser);
        vault.unpauseCreate();
        assertFalse(vault.createPaused());
        _create(1e18);
    }

    function test_pauseCreate_isIndependentOfPause() public {
        vm.prank(pauser);
        vault.pauseCreate();
        vm.prank(pauser);
        vault.pause();
        vm.prank(unpauser);
        vault.unpause();
        assertTrue(vault.createPaused());
        vm.expectRevert(IBasketVault.CreationPaused.selector);
        _create(1e18);
    }

    // =============================================================
    // UUPS upgrade
    // =============================================================

    function test_upgrade_byUpgraderKeepsState() public {
        _create(100e18);
        BasketVaultV2Mock v2 = new BasketVaultV2Mock();
        vm.prank(upgrader);
        vault.upgradeToAndCall(address(v2), "");

        assertEq(BasketVaultV2Mock(address(vault)).version(), 2);
        (uint32 version, IBasketVault.Leg[] memory legs) = vault.legs();
        assertEq(version, 1);
        assertEq(legs[1].qtyPerUnit, GOLD_QTY);
        _redeem(10e18);
        _assertBacked();
    }

    function test_upgrade_revertsWithoutUpgraderRole() public {
        BasketVaultV2Mock v2 = new BasketVaultV2Mock();
        _expectMissingRole(admin, Roles.UPGRADER_ROLE);
        vm.prank(admin);
        vault.upgradeToAndCall(address(v2), "");
    }
}
