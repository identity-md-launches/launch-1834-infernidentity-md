// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {InfernToken} from "src/InfernToken.sol";

/// @dev A real contract caller for checking that authorization belongs to msg.sender.
contract InfernSpenderFixture {
    function pull(InfernToken token, address from, address to, uint256 amount)
        external
        returns (bool)
    {
        return token.transferFrom(from, to, amount);
    }
}

/// forge-config: default.fuzz.runs = 1000
contract InfernTokenAdversarialTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    InfernToken internal token;
    address internal alice = makeAddr("adversarial alice");
    address internal bob = makeAddr("adversarial bob");
    address internal spender = makeAddr("adversarial spender");
    address internal otherSpender = makeAddr("adversarial other spender");

    function setUp() public {
        token = new InfernToken();
    }

    function test_OneWeiCanBeTransferredAndReturnedThroughAnAllowance() public {
        assertTrue(token.transfer(alice, 1));
        assertEq(token.balanceOf(alice), 1);
        assertEq(token.balanceOf(address(this)), SUPPLY - 1);

        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, address(this), 1));
        _assertBalances(SUPPLY, 0, 0);
        assertEq(token.allowance(alice, spender), 0);
    }

    function test_MaximumTransferCannotWrapBalancesEvenForSelfTransfer() public {
        bytes memory errorData = abi.encodeWithSelector(
            IERC20Errors.ERC20InsufficientBalance.selector, address(this), SUPPLY, type(uint256).max
        );
        vm.expectRevert(errorData);
        token.transfer(alice, type(uint256).max);
        _assertBalances(SUPPLY, 0, 0);

        vm.expectRevert(errorData);
        token.transfer(address(this), type(uint256).max);
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_MaximumMinusOneAllowanceIsFiniteAcrossRepeatedSpends() public {
        assertTrue(token.approve(spender, type(uint256).max - 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 2);
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 2));
        assertEq(token.allowance(address(this), spender), type(uint256).max - 4);
        _assertBalances(SUPPLY - 3, 1, 2);
    }

    function test_MaximumDelegatedTransferCannotOverdrawAnUnlimitedApproval() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector,
                address(this),
                SUPPLY,
                type(uint256).max
            )
        );
        vm.prank(spender);
        token.transferFrom(address(this), alice, type(uint256).max);
        assertEq(token.allowance(address(this), spender), type(uint256).max);
        _assertBalances(SUPPLY, 0, 0);
    }

    function test_ReducingUnlimitedApprovalMakesSubsequentSpendingFinite() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertTrue(token.approve(spender, 2));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), bob, 2));
        assertEq(token.allowance(address(this), spender), 0);

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        _assertBalances(SUPPLY - 3, 1, 2);
    }

    function test_RevokingUnlimitedApprovalEmitsEventAndPreventsFurtherSpending() public {
        assertTrue(token.approve(spender, type(uint256).max));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));

        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(address(this), spender, 0);
        assertTrue(token.approve(spender, 0));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(address(this), bob, 1);
        assertEq(token.allowance(address(this), spender), 0);
        _assertBalances(SUPPLY - 1, 1, 0);
    }

    function test_ExhaustedAllowanceCannotBeSpentAgainAfterHolderIsRefilled() public {
        assertTrue(token.transfer(alice, 1));
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertTrue(token.transfer(alice, 1));

        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, spender, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, spender), 0);
        _assertBalances(SUPPLY - 2, 1, 1);
    }

    function test_DelegatedSelfTransferStillRequiresEnoughBalance() public {
        assertTrue(token.transfer(alice, 1));
        vm.prank(alice);
        assertTrue(token.approve(spender, 2));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 1, 2)
        );
        vm.prank(spender);
        token.transferFrom(alice, alice, 2);
        assertEq(token.allowance(alice, spender), 2);
        _assertBalances(SUPPLY - 1, 1, 0);
    }

    function test_SpenderCannotRedelegateAnotherHoldersApproval() public {
        assertTrue(token.transfer(alice, 10));
        vm.prank(alice);
        assertTrue(token.approve(spender, 10));
        vm.prank(spender);
        assertTrue(token.approve(otherSpender, type(uint256).max));

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, otherSpender, 0, 1
            )
        );
        vm.prank(otherSpender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, spender), 10);
        assertEq(token.allowance(alice, otherSpender), 0);
        assertEq(token.allowance(spender, otherSpender), type(uint256).max);
        _assertBalances(SUPPLY - 10, 10, 0);
    }

    function test_ContractSpenderNeedsItsOwnApprovalEvenWithAuthorizedOrigin() public {
        InfernSpenderFixture proxy = new InfernSpenderFixture();
        assertTrue(token.approve(alice, 1));
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, address(proxy), 0, 1
            )
        );
        vm.prank(alice, alice);
        proxy.pull(token, address(this), bob, 1);
        _assertBalances(SUPPLY, 0, 0);
        assertEq(token.allowance(address(this), alice), 1);

        assertTrue(token.approve(address(proxy), 1));
        vm.prank(alice, alice);
        assertTrue(proxy.pull(token, address(this), bob, 1));
        assertEq(token.allowance(address(this), address(proxy)), 0);
        assertEq(token.allowance(address(this), alice), 1);
        _assertBalances(SUPPLY - 1, 0, 1);
    }

    function test_FailedDelegatedTransferDoesNotConsumeApprovalAndCanBeRetried() public {
        vm.prank(alice);
        assertTrue(token.approve(spender, 1));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1)
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, 1);
        assertEq(token.allowance(alice, spender), 1);

        assertTrue(token.transfer(alice, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, bob, 1));
        assertEq(token.allowance(alice, spender), 0);
        _assertBalances(SUPPLY - 1, 0, 1);
    }

    function test_ApprovalCanBeRestoredAfterRevocation() public {
        assertTrue(token.approve(spender, 1));
        assertTrue(token.approve(spender, 0));
        assertTrue(token.approve(spender, 1));
        vm.prank(spender);
        assertTrue(token.transferFrom(address(this), alice, 1));
        assertEq(token.allowance(address(this), spender), 0);
        _assertBalances(SUPPLY - 1, 1, 0);
    }

    function test_ZeroDelegatedSelfTransferPreservesFiniteAndUnlimitedApprovals() public {
        vm.startPrank(alice);
        assertTrue(token.approve(spender, 1));
        assertTrue(token.approve(otherSpender, type(uint256).max));
        vm.stopPrank();
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, alice, 0));
        vm.prank(otherSpender);
        assertTrue(token.transferFrom(alice, alice, 0));
        assertEq(token.allowance(alice, spender), 1);
        assertEq(token.allowance(alice, otherSpender), type(uint256).max);
        _assertBalances(SUPPLY, 0, 0);
    }

    function testFuzz_AllowanceReplacementIsIsolatedToOwnerAndSpender(
        uint256 initial,
        uint256 unrelated,
        uint256 replacement
    ) public {
        assertTrue(token.approve(spender, initial));
        assertTrue(token.approve(otherSpender, unrelated));
        vm.prank(alice);
        assertTrue(token.approve(spender, unrelated));

        vm.expectEmit(true, true, false, true, address(token));
        emit IERC20.Approval(address(this), spender, replacement);
        assertTrue(token.approve(spender, replacement));
        assertEq(token.allowance(address(this), spender), replacement);
        assertEq(token.allowance(address(this), otherSpender), unrelated);
        assertEq(token.allowance(alice, spender), unrelated);
        assertEq(token.allowance(spender, address(this)), 0);
        _assertBalances(SUPPLY, 0, 0);
    }

    function testFuzz_OverdrawRollsBackLargeFiniteAllowance(
        uint256 funded,
        uint256 attempted,
        uint256 approved
    ) public {
        funded = bound(funded, 0, SUPPLY);
        attempted = bound(attempted, funded + 1, type(uint256).max - 1);
        approved = bound(approved, attempted, type(uint256).max - 1);
        assertTrue(token.transfer(alice, funded));
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));

        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, alice, funded, attempted
            )
        );
        vm.prank(spender);
        token.transferFrom(alice, bob, attempted);
        assertEq(token.allowance(alice, spender), approved);
        _assertBalances(SUPPLY - funded, funded, 0);
    }

    function testFuzz_InvalidRecipientRollsBackAllowance(uint256 approved, uint256 amount) public {
        amount = bound(amount, 0, approved < SUPPLY ? approved : SUPPLY);
        assertTrue(token.approve(spender, approved));
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        vm.prank(spender);
        token.transferFrom(address(this), address(0), amount);
        assertEq(token.allowance(address(this), spender), approved);
        _assertBalances(SUPPLY, 0, 0);
    }

    function testFuzz_DelegatedSelfTransferChangesOnlyFiniteAllowance(
        uint256 funded,
        uint256 approved,
        uint256 spent
    ) public {
        funded = bound(funded, 0, SUPPLY);
        spent = bound(spent, 0, approved < funded ? approved : funded);
        assertTrue(token.transfer(alice, funded));
        vm.prank(alice);
        assertTrue(token.approve(spender, approved));
        vm.prank(spender);
        assertTrue(token.transferFrom(alice, alice, spent));
        assertEq(
            token.allowance(alice, spender),
            approved == type(uint256).max ? approved : approved - spent
        );
        _assertBalances(SUPPLY - funded, funded, 0);
    }

    function _assertBalances(uint256 deployerBalance, uint256 aliceBalance, uint256 bobBalance)
        internal
        view
    {
        assertEq(token.balanceOf(address(this)), deployerBalance);
        assertEq(token.balanceOf(alice), aliceBalance);
        assertEq(token.balanceOf(bob), bobBalance);
        assertEq(token.balanceOf(spender), 0);
        assertEq(token.balanceOf(otherSpender), 0);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.totalSupply(), SUPPLY);
    }
}
