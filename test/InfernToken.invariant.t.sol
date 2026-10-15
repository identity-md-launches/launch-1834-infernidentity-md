// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {InfernToken} from "../src/InfernToken.sol";

/// @dev Model balances and allowances independently across arbitrary operation sequences.
contract InfernTokenHandler is Test {
    InfernToken internal immutable token;
    address[4] internal actors;
    mapping(address => uint256) public expectedBalance;
    mapping(address => mapping(address => uint256)) public expectedAllowance;

    constructor(InfernToken token_, address[4] memory actors_) {
        token = token_;
        actors = actors_;
        expectedBalance[actors_[0]] = 1_000_000_000 * 10 ** 18;
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] -= amount;
        expectedBalance[to] += amount;
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 amount, bool unlimited)
        external
    {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        // Approvals are not capped by supply. In particular, max - 1 is still finite.
        amount = unlimited ? type(uint256).max : bound(amount, 0, type(uint256).max - 1);
        vm.prank(owner);
        assertTrue(token.approve(spender, amount));
        expectedAllowance[owner][spender] = amount;
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amount)
        external
    {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 approved = expectedAllowance[owner][spender];
        uint256 balance = expectedBalance[owner];
        amount = bound(amount, 0, approved < balance ? approved : balance);
        vm.prank(spender);
        assertTrue(token.transferFrom(owner, to, amount));
        expectedBalance[owner] -= amount;
        expectedBalance[to] += amount;
        if (approved != type(uint256).max) {
            expectedAllowance[owner][spender] -= amount;
        }
    }

    function overdraw(uint256 fromSeed, uint256 toSeed) external {
        address from = actors[fromSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[from];
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, from, balance, balance + 1
            )
        );
        vm.prank(from);
        token.transfer(to, balance + 1);
    }

    function overspend(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 approved = expectedAllowance[owner][spender];
        if (approved == type(uint256).max) return;
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, approved + 1
            )
        );
        vm.prank(spender);
        token.transferFrom(owner, to, approved + 1);
    }

    function revoke(uint256 ownerSeed, uint256 spenderSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        vm.prank(owner);
        assertTrue(token.approve(spender, 0));
        expectedAllowance[owner][spender] = 0;
    }

    function transferAll(uint256 fromSeed, uint256 toSeed) external {
        uint256 fromIndex = fromSeed % actors.length;
        address from = actors[fromIndex];
        // Always choose a different recipient to exercise emptying and refilling accounts.
        address to = actors[(fromIndex + 1 + toSeed % (actors.length - 1)) % actors.length];
        uint256 amount = expectedBalance[from];
        vm.prank(from);
        assertTrue(token.transfer(to, amount));
        expectedBalance[from] = 0;
        expectedBalance[to] += amount;
    }

    function transferToZero(uint256 fromSeed, uint256 amount) external {
        address from = actors[fromSeed % actors.length];
        amount = bound(amount, 0, expectedBalance[from]);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        vm.prank(from);
        token.transfer(address(0), amount);
        // Leave ghosts untouched: the next invariant checks the entire ledger for rollback.
    }

    function transferFromToZero(uint256 ownerSeed, uint256 spenderSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        uint256 approved = expectedAllowance[owner][spender];
        uint256 balance = expectedBalance[owner];
        amount = bound(amount, 0, approved < balance ? approved : balance);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0))
        );
        vm.prank(spender);
        token.transferFrom(owner, address(0), amount);
    }

    function approveZeroSpender(uint256 ownerSeed, uint256 amount) external {
        address owner = actors[ownerSeed % actors.length];
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InvalidSpender.selector, address(0))
        );
        vm.prank(owner);
        token.approve(address(0), amount);
    }

    function overdrawFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed) external {
        address owner = actors[ownerSeed % actors.length];
        address spender = actors[spenderSeed % actors.length];
        address to = actors[toSeed % actors.length];
        uint256 balance = expectedBalance[owner];
        uint256 attempted = balance + 1;
        uint256 approved = expectedAllowance[owner][spender];
        if (approved < attempted) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IERC20Errors.ERC20InsufficientAllowance.selector, spender, approved, attempted
                )
            );
        } else {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IERC20Errors.ERC20InsufficientBalance.selector, owner, balance, attempted
                )
            );
        }
        vm.prank(spender);
        token.transferFrom(owner, to, attempted);
    }
}

/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract InfernTokenInvariantTest is Test {
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    InfernToken internal token;
    InfernTokenHandler internal handler;
    address[4] internal actors;

    function setUp() public {
        actors = [
            makeAddr("holder 0"), makeAddr("holder 1"), makeAddr("holder 2"), makeAddr("holder 3")
        ];
        vm.prank(actors[0]);
        token = new InfernToken();
        handler = new InfernTokenHandler(token, actors);

        // Use real transfers and approvals to start with funded and empty accounts,
        // plus small finite, large finite, unlimited and absent authorizations.
        handler.transfer(0, 1, SUPPLY / 4);
        handler.transfer(0, 2, SUPPLY / 4);
        handler.approve(0, 1, SUPPLY / 2, false);
        handler.approve(1, 2, 0, true);
        handler.approve(2, 3, type(uint256).max - 1, false);

        bytes4[] memory selectors = new bytes4[](11);
        selectors[0] = InfernTokenHandler.transfer.selector;
        selectors[1] = InfernTokenHandler.approve.selector;
        selectors[2] = InfernTokenHandler.transferFrom.selector;
        selectors[3] = InfernTokenHandler.overdraw.selector;
        selectors[4] = InfernTokenHandler.overspend.selector;
        selectors[5] = InfernTokenHandler.revoke.selector;
        selectors[6] = InfernTokenHandler.transferAll.selector;
        selectors[7] = InfernTokenHandler.transferToZero.selector;
        selectors[8] = InfernTokenHandler.transferFromToZero.selector;
        selectors[9] = InfernTokenHandler.approveZeroSpender.selector;
        selectors[10] = InfernTokenHandler.overdrawFrom.selector;
        targetContract(address(handler));
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    function invariant_SupplyAndBalancesAreConserved() public view {
        uint256 aggregate;
        for (uint256 i; i < actors.length; ++i) {
            uint256 balance = token.balanceOf(actors[i]);
            assertEq(balance, handler.expectedBalance(actors[i]));
            aggregate += balance;
        }
        assertEq(aggregate, SUPPLY);
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.balanceOf(address(0)), 0);
        assertEq(token.balanceOf(address(token)), 0);
        assertEq(token.balanceOf(address(handler)), 0);
        assertEq(token.balanceOf(address(this)), 0);
    }

    function invariant_AllowancesMatchOnlyHolderAuthorizationsAndSpending() public view {
        for (uint256 i; i < actors.length; ++i) {
            assertEq(token.allowance(actors[i], address(0)), 0);
            assertEq(token.allowance(address(0), actors[i]), 0);
            for (uint256 j; j < actors.length; ++j) {
                assertEq(
                    token.allowance(actors[i], actors[j]),
                    handler.expectedAllowance(actors[i], actors[j])
                );
            }
        }
    }

    function invariant_MetadataNeverChanges() public view {
        assertEq(token.name(), "Infernidentity.md");
        assertEq(token.symbol(), "INFERN");
        assertEq(token.decimals(), 18);
        assertEq(token.INITIAL_SUPPLY(), SUPPLY);
    }

    function afterInvariant() public {
        // Every holder must still be able to move its full balance after the sequence.
        handler.transfer(0, 1, handler.expectedBalance(actors[0]));
        for (uint256 i = 1; i < actors.length; ++i) {
            handler.transfer(i, 0, handler.expectedBalance(actors[i]));
        }
        assertEq(token.balanceOf(actors[0]), SUPPLY);
        invariant_SupplyAndBalancesAreConserved();
        invariant_AllowancesMatchOnlyHolderAuthorizationsAndSpending();
        invariant_MetadataNeverChanges();
    }

    function test_HandlerSequenceExercisesAuthorizationAndRollback() public {
        // Pin meaningful nonzero operations independently of random selector frequency.
        handler.transferFrom(0, 1, 3, 1);
        assertEq(token.balanceOf(actors[3]), 1);
        assertEq(token.allowance(actors[0], actors[1]), SUPPLY / 2 - 1);
        invariant_SupplyAndBalancesAreConserved();
        invariant_AllowancesMatchOnlyHolderAuthorizationsAndSpending();

        handler.overdrawFrom(1, 2, 3);
        handler.transferFromToZero(1, 2, 1);
        handler.transferFromToZero(2, 3, 1);
        invariant_SupplyAndBalancesAreConserved();
        invariant_AllowancesMatchOnlyHolderAuthorizationsAndSpending();

        handler.revoke(1, 2);
        handler.overspend(1, 2, 3);
        assertEq(token.allowance(actors[1], actors[2]), 0);
        handler.transferAll(3, 0);
        assertEq(token.balanceOf(actors[3]), 0);
        afterInvariant();
    }
}
