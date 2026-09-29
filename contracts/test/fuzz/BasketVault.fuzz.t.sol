// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IBasketVault} from "../../src/interfaces/IBasketVault.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {BasketVaultTestBase} from "../unit/BasketVault.t.sol";

/// @notice Fuzz tests for BasketVault (L1 section 6): amount and rounding edges, fee-on-transfer gold, and a USD
///         leg with 6 or 18 decimals. Every run checks INV-1 and that rounding goes against the user.
contract BasketVaultFuzzTest is BasketVaultTestBase {
    function _redeploy(bool usd18) internal {
        if (usd18) {
            usdc = new MockERC20("USD 18", "USD18", 18);
            IBasketVault.Leg[] memory legs = new IBasketVault.Leg[](2);
            legs[0] = IBasketVault.Leg(address(usdc), 0.7e18);
            legs[1] = IBasketVault.Leg(address(gold), GOLD_QTY);
            _deploy(legs);
        }
    }

    function testFuzz_create_pullsAtLeastExactAndStaysBacked(uint256 amount, uint16 goldFeeBps, bool usd18) public {
        _redeploy(usd18);
        amount = bound(amount, 1, TIER1_LIMIT);
        gold.setTransferFeeBps(uint16(bound(goldFeeBps, 0, 500)));
        (, IBasketVault.Leg[] memory legs) = vault.legs();

        uint256 out = _create(amount);

        uint256 supply = knd.totalSupply();
        assertLe(supply, amount, "gross capped at kndAmount");
        assertEq(out, supply - Math.mulDiv(supply, FEE_BPS, 10_000, Math.Rounding.Ceil), "net = gross - ceil fee");
        // The USD leg has no transfer fee, so the vault's balance is exactly what was pulled: at least the exact
        // amount for the requested KND, rounded up.
        uint256 usdPulled = usdc.balanceOf(address(vault));
        assertGe(usdPulled * 1e18, amount * legs[0].qtyPerUnit, "pulled rounds up");
        assertEq(usdPulled, Math.mulDiv(amount, legs[0].qtyPerUnit, 1e18, Math.Rounding.Ceil));
        if (goldFeeBps == 0) assertEq(supply, amount, "no fee-on-transfer: full mint");
        _assertBacked();
    }

    function testFuzz_createRedeem_staysBacked(
        uint256 createAmount,
        uint256 redeemAmount,
        uint16 goldFeeBps,
        bool usd18
    ) public {
        _redeploy(usd18);
        gold.setTransferFeeBps(uint16(bound(goldFeeBps, 0, 500)));
        createAmount = bound(createAmount, 1, TIER1_LIMIT);
        uint256 net = _create(createAmount);
        vm.assume(net > 0);
        redeemAmount = bound(redeemAmount, 1, net);

        (, IBasketVault.Leg[] memory legs) = vault.legs();
        uint256[] memory preview = vault.previewRedeem(redeemAmount);
        uint256 redeemNet = redeemAmount - Math.mulDiv(redeemAmount, FEE_BPS, 10_000, Math.Rounding.Ceil);

        uint256[] memory out = _redeem(redeemAmount);

        for (uint256 i; i < legs.length; ++i) {
            assertEq(out[i], preview[i], "preview matches");
            assertLe(out[i] * 1e18, redeemNet * legs[i].qtyPerUnit, "payout rounds down");
        }
        _assertBacked();
    }

    function testFuzz_coverage_neverBelowFullAfterOps(uint256 a, uint256 b, uint256 c) public {
        _create(bound(a, 1, 10_000e18));
        _create(bound(b, 1, 10_000e18));
        uint256 bal = knd.balanceOf(ap);
        vm.assume(bal > 0);
        _redeem(bound(c, 1, bal));

        uint256[] memory ratios = vault.coverage();
        for (uint256 i; i < ratios.length; ++i) {
            assertGe(ratios[i], 10_000);
        }
        _assertBacked();
    }
}
