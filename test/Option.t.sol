// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "../lib/forge-std/src/Test.sol";
import {MockOracleFeed} from "../src/mocks/MockOracleFeed.sol";
import {Option} from "../src/Option.sol";

contract OptionTest is Test {
    MockOracleFeed public mockOracleFeed;
    Option public option;

    function setUp() public returns (address, address) {
        // Create addresses for deployer, buyer, and randomUser
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");

        // Fund each address with 100 ETH
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);

        return (user1, user2);
    }

    /**
     * @notice Set up the oracle feed for the option
     * @dev The starting price is 120
     * @return MockOracleFeed The mock oracle feed
     */
    function _setUpOracle() internal returns (MockOracleFeed) {
        mockOracleFeed = new MockOracleFeed(18, "Mock Oracle Feed");

        // simulate passing 1 hour and add a round
        vm.warp(block.timestamp + 1 hours);
        mockOracleFeed.addRound(110);

        // simulate passing 1 hour and add a round
        vm.warp(block.timestamp + 1 hours);
        mockOracleFeed.addRound(120);

        return mockOracleFeed;
    }

    function testFuzz_OptionExpires(
        uint256 _value,
        uint256 _heartbeat,
        int256 _strikePrice,
        uint256 _expirationTimestamp
    ) public {
        (address user1,) = setUp();
        mockOracleFeed = _setUpOracle();

        _value = bound(_value, 1, 50 ether);
        _heartbeat = bound(_heartbeat, 1 minutes, 365 days);
        _strikePrice = int256(bound(uint256(_strikePrice), 1, 1_000 ether));
        _expirationTimestamp = bound(_expirationTimestamp, block.timestamp + 1 minutes, block.timestamp + 365 days);

        vm.assume(_heartbeat != 0);
        vm.assume(_strikePrice != 120);
        vm.assume(_expirationTimestamp > block.timestamp + 1 minutes);

        // start an option with a heartbeat of 1 hour, a fuzzed strike price, and an expiry time of 3 days from now
        option = new Option{value: _value}(address(mockOracleFeed), _heartbeat, _strikePrice, _expirationTimestamp);

        // assert that the contract has the correct amount of value
        assertEq(address(option).balance, _value);

        // assert that the feed parameters are all correct
        (address feed, uint256 heartbeat) = option.getFeedParameters();
        assertEq(feed, address(mockOracleFeed));
        assertEq(heartbeat, _heartbeat);

        // assert that the option parameters are all correct
        (Option.OptionType optionType, int256 startingPrice, int256 strikePrice, uint256 expiration) =
            option.getOptionParameters();
        if (_strikePrice > 120) {
            assertEq(uint256(optionType), uint256(Option.OptionType.CALL));
        } else {
            assertEq(uint256(optionType), uint256(Option.OptionType.PUT));
        }
        assertEq(startingPrice, 120);
        assertEq(strikePrice, _strikePrice);
        assertEq(expiration, _expirationTimestamp);

        // assert that the deal parameters are all correct
        (address buyer, address seller, uint256 amount, address winner) = option.getDealParameters();
        assertEq(buyer, address(0));
        assertEq(seller, address(this));
        assertEq(amount, _value);
        assertEq(winner, address(0));

        // buy the option
        vm.prank(user1);
        option.buy{value: _value}();

        // assert that the contract has the correct amount of value
        assertEq(address(option).balance, _value * 2);

        // assert that the deal parameters are all correct
        (buyer, seller, amount, winner) = option.getDealParameters();
        assertEq(buyer, address(user1));
        assertEq(seller, address(this));
        assertEq(amount, _value);
        assertEq(winner, address(0));

        // simulate passing time until the option expires
        vm.warp(_expirationTimestamp);

        // try to finalize the option (as the buyer)
        vm.prank(user1);
        option.tryFinalize();

        // assert that the option is finalized
        (buyer, seller, amount, winner) = option.getDealParameters();
        assertEq(winner, address(this));

        // withdraw the total funds and assert that the balances are correct
        uint256 thisBalanceBefore = address(this).balance;
        vm.prank(address(this));
        option.withdraw(_value * 2);
        assertEq(address(option).balance, 0);
        assertEq(address(this).balance, thisBalanceBefore + _value * 2);
    }

    function testFuzz_OptionHitStrikePrice(
        uint256 _value,
        uint256 _heartbeat,
        int256 _strikePrice,
        uint256 _expirationTimestamp
    ) public {
        (address user1,) = setUp();
        mockOracleFeed = _setUpOracle();

        _value = bound(_value, 1, 50 ether);
        _heartbeat = bound(_heartbeat, 1 minutes, 365 days);
        _strikePrice = int256(bound(uint256(_strikePrice), 1, 1_000 ether));
        _expirationTimestamp = bound(_expirationTimestamp, block.timestamp + 1 minutes, block.timestamp + 365 days);

        vm.assume(_heartbeat != 0);
        vm.assume(_strikePrice != 120);
        vm.assume(_expirationTimestamp > block.timestamp + 1 minutes);

        // start an option with a heartbeat of 1 hour, a fuzzed strike price, and an expiry time of 3 days from now
        option = new Option{value: _value}(address(mockOracleFeed), _heartbeat, _strikePrice, _expirationTimestamp);

        // assert that the contract has the correct amount of value
        assertEq(address(option).balance, _value);

        // assert that the feed parameters are all correct
        (address feed, uint256 heartbeat) = option.getFeedParameters();
        assertEq(feed, address(mockOracleFeed));
        assertEq(heartbeat, _heartbeat);

        // assert that the option parameters are all correct
        (Option.OptionType optionType, int256 startingPrice, int256 strikePrice, uint256 expiration) =
            option.getOptionParameters();
        if (_strikePrice > 120) {
            assertEq(uint256(optionType), uint256(Option.OptionType.CALL));
        } else {
            assertEq(uint256(optionType), uint256(Option.OptionType.PUT));
        }
        assertEq(startingPrice, 120);
        assertEq(strikePrice, _strikePrice);
        assertEq(expiration, _expirationTimestamp);

        // assert that the deal parameters are all correct
        (address buyer, address seller, uint256 amount, address winner) = option.getDealParameters();
        assertEq(buyer, address(0));
        assertEq(seller, address(this));
        assertEq(amount, _value);
        assertEq(winner, address(0));

        // buy the option
        vm.prank(user1);
        option.buy{value: _value}();

        // assert that the contract has the correct amount of value
        assertEq(address(option).balance, _value * 2);

        // assert that the deal parameters are all correct
        (buyer, seller, amount, winner) = option.getDealParameters();
        assertEq(buyer, address(user1));
        assertEq(seller, address(this));
        assertEq(amount, _value);
        assertEq(winner, address(0));

        // simulate passing time one more hour and add a round that hits the strike price
        vm.warp(_expirationTimestamp - 1);
        mockOracleFeed.addRound(_strikePrice);

        // try to finalize the option (as the seller)
        vm.prank(address(this));
        option.tryFinalize();

        // assert that the option is finalized
        (buyer, seller, amount, winner) = option.getDealParameters();
        assertEq(winner, user1);

        // withdraw the total funds and assert that the balances are correct
        uint256 user1BalanceBefore = user1.balance;
        vm.prank(user1);
        option.withdraw(_value * 2);
        assertEq(address(option).balance, 0);
        assertEq(user1.balance, user1BalanceBefore + _value * 2);
    }

    function testFuzz_OptionCanceled(
        uint256 _value,
        uint256 _heartbeat,
        int256 _strikePrice,
        uint256 _expirationTimestamp
    ) public {
        (address user1,) = setUp();
        mockOracleFeed = _setUpOracle();

        _value = bound(_value, 1, 50 ether);
        _heartbeat = bound(_heartbeat, 1 minutes, 365 days);
        _strikePrice = int256(bound(uint256(_strikePrice), 1, 1_000 ether));
        _expirationTimestamp = bound(_expirationTimestamp, block.timestamp + 1 minutes, block.timestamp + 365 days);

        vm.assume(_heartbeat != 0);
        vm.assume(_strikePrice != 120);
        vm.assume(_expirationTimestamp > block.timestamp + 1 minutes);

        // start an option with a heartbeat of 1 hour, a fuzzed strike price, and an expiry time of 3 days from now
        option = new Option{value: _value}(address(mockOracleFeed), _heartbeat, _strikePrice, _expirationTimestamp);

        // assert that the contract has the correct amount of value
        assertEq(address(option).balance, _value);

        // assert that the feed parameters are all correct
        (address feed, uint256 heartbeat) = option.getFeedParameters();
        assertEq(feed, address(mockOracleFeed));
        assertEq(heartbeat, _heartbeat);

        // assert that the option parameters are all correct
        (Option.OptionType optionType, int256 startingPrice, int256 strikePrice, uint256 expiration) =
            option.getOptionParameters();
        if (_strikePrice > 120) {
            assertEq(uint256(optionType), uint256(Option.OptionType.CALL));
        } else {
            assertEq(uint256(optionType), uint256(Option.OptionType.PUT));
        }
        assertEq(startingPrice, 120);
        assertEq(strikePrice, _strikePrice);
        assertEq(expiration, _expirationTimestamp);

        // assert that the deal parameters are all correct
        (address buyer, address seller, uint256 amount, address winner) = option.getDealParameters();
        assertEq(buyer, address(0));
        assertEq(seller, address(this));
        assertEq(amount, _value);
        assertEq(winner, address(0));

        // simulate passing time one more hour and have the seller cancel
        vm.warp(_expirationTimestamp - 100);
        vm.prank(address(this));
        option.cancel();

        // assert that the option is canceled
        bool isCanceled = option.isCanceled();
        assertEq(isCanceled, true);

        // assert that the contract has the correct amount of value
        assertEq(address(option).balance, _value);

        // assert that the deal parameters are all correct
        (buyer, seller, amount, winner) = option.getDealParameters();
        assertEq(winner, address(this));

        // try to buy the option as user1; it should revert
        vm.prank(user1);
        vm.expectRevert(Option.ErrorOptionCanceled.selector);
        option.buy{value: _value}();

        // withdraw the total funds and assert that the balances are correct
        uint256 thisBalanceBefore = address(this).balance;
        vm.prank(address(this));
        option.withdraw(_value);
        assertEq(address(option).balance, 0);
        assertEq(address(this).balance, thisBalanceBefore + _value);
    }

    function test_constructor_reverts_on_feed_address_zero() public {
        vm.expectRevert(Option.ErrorFeedAddressZero.selector);
        new Option{value: 1 ether}(address(0), 1 hours, 140, block.timestamp + 3 days);
    }

    function test_constructor_reverts_on_heartbeat_zero() public {
        mockOracleFeed = _setUpOracle();
        vm.expectRevert(Option.ErrorHeartbeatZero.selector);
        new Option{value: 1 ether}(address(mockOracleFeed), 0, 140, block.timestamp + 3 days);
    }

    function test_constructor_reverts_on_feed_not_live() public {
        mockOracleFeed = _setUpOracle();

        // Case 1: Latest timestamp is 0
        MockOracleFeed zeroTimestampFeed = new MockOracleFeed(18, "Zero Timestamp Feed");
        vm.expectRevert();
        new Option{value: 1 ether}(address(zeroTimestampFeed), 1 hours, 140, block.timestamp + 3 days);

        // Case 2: Latest timestamp is in the future
        MockOracleFeed futureFeed = new MockOracleFeed(18, "Future Feed");
        futureFeed.addRoundWithTimestamp(120, block.timestamp + 1 hours);
        vm.expectRevert(Option.ErrorFeedNotLive.selector);
        new Option{value: 1 ether}(address(futureFeed), 1 hours, 140, block.timestamp + 3 days);

        // Case 3: Latest timestamp is older than the heartbeat
        MockOracleFeed oldFeed = new MockOracleFeed(18, "Old Feed");
        oldFeed.addRoundWithTimestamp(120, block.timestamp - 1 hours - 1 seconds);
        vm.expectRevert(Option.ErrorFeedNotLive.selector);
        new Option{value: 1 ether}(address(oldFeed), 1 hours, 140, block.timestamp + 3 days);

        // Case 4: Feed is live (should not revert)
        MockOracleFeed liveFeed = new MockOracleFeed(18, "Live Feed");
        liveFeed.addRoundWithTimestamp(120, block.timestamp - 30 minutes);
        new Option{value: 1 ether}(address(liveFeed), 1 hours, 140, block.timestamp + 3 days);
    }

    function test_constructor_reverts_on_strike_price_equal_to_latest_price() public {
        mockOracleFeed = _setUpOracle();
        vm.expectRevert(Option.ErrorStrikePriceEqualLatestPrice.selector);
        new Option{value: 1 ether}(address(mockOracleFeed), 1 hours, 120, block.timestamp + 3 days);
    }

    function test_constructor_reverts_on_expiration_before_expiration_delay() public {
        mockOracleFeed = _setUpOracle();
        vm.expectRevert(Option.ErrorExpirationBeforeExpirationDelay.selector);
        new Option{value: 1 ether}(address(mockOracleFeed), 1 hours, 140, block.timestamp + 1 minutes);
    }

    receive() external payable {}
}
