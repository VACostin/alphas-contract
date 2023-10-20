// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

interface TokenI {
    function transfer(address to, uint256 amount) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    function balanceOf(address to) external returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function decimals() external view returns (uint8);
}

//*******************************************************************//
//------------------ Contract to Manage Ownership -------------------//
//*******************************************************************//

/**
 * @title Ownable
 * @dev The Ownable contract has an owner address, and provides basic authorization control
 * functions, this simplifies the implementation of "user permissions".
 */
contract Ownable {
    address private _owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    /**
     * @dev The Ownable constructor sets the original `owner` of the contract to the sender
     * account.
     */
    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), _owner);
    }

    /**
     * @return the address of the owner.
     */
    function owner() public view returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(isOwner());
        _;
    }

    /**
     * @return true if `msg.sender` is the owner of the contract.
     */
    function isOwner() public view returns (bool) {
        return msg.sender == _owner;
    }

    /**
     * @dev Allows the current owner to relinquish control of the contract.
     * It will not be possible to call the functions with the `onlyOwner`
     * modifier anymore.
     * @notice Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Allows the current owner to transfer control of the contract to a newOwner.
     * @param newOwner The address to transfer ownership to.
     */
    function transferOwnership(address newOwner) public onlyOwner {
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers control of the contract to a newOwner.
     * @param newOwner The address to transfer ownership to.
     */
    function _transferOwnership(address newOwner) internal {
        require(newOwner != address(0));
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

/**
 * @dev To Main Stake contract  .
 */
contract Stake is Ownable {
    struct _staking {
        uint256 _id;
        uint256 _startTime;
        uint256 _claimTime;
        uint256 _amount;
        uint256 _APY;
    }
    address public rewardPoolAddress;
    address public tokenAddress = address(0);
    mapping(address => mapping(uint256 => _staking)) public staking;
    mapping(address => uint256) public activeStake;
    uint8 private decimalsAPY = 18;
    uint256 private maxAPY = 100;
    uint256 private minAPY = 8;
    uint256 private APY = maxAPY;
    uint256 private initialSupply = 150000000000 * 10 ** 18;
    uint256 breakpoint = initialSupply / 10;
    uint256 private rewardPoolBal = initialSupply;
    uint256 private stakeBalance;
    uint256 private lastStake = 0;
    uint32 private oneWeek = 7 * 24 * 60 * 60;
    uint32 private oneMonth = 30 * 24 * 60 * 60;
    uint32 private oneYear = 365 * 24 * 60 * 60;

    constructor(address _tokenContract) {
        tokenAddress = _tokenContract;
        rewardPoolAddress = address(this);
    }

    /**
     * @dev To show contract event  .
     */
    event StakeEvent(uint256 _stakeid, address _to, uint _stakeamount);
    event Unstake(uint256 _stakeid, address _to, uint _amount);
    event Claim(uint256 _stakeid, address _to, uint _claimamount);

    /**
     * @dev updates pool and apy.
     */
    function _updateRewards(uint256 amount, bool isPositive) internal {
        if (isPositive) {
            rewardPoolBal += amount;
        } else {
            rewardPoolBal -= amount;
        }
        if (rewardPoolBal >= initialSupply) {
            APY = maxAPY;
        }
        if (rewardPoolBal >= breakpoint) {
            APY =
                minAPY +
                ((((rewardPoolBal - breakpoint) * 10 ** decimalsAPY) /
                    (initialSupply - breakpoint)) * (maxAPY - minAPY)) /
                10 ** decimalsAPY;
        } else {
            APY = minAPY;
        }
    }

    /**
     * @dev returns APY for new users.
     */
    function currentAPY() public view returns (uint) {
        return APY;
    }

    /**
     * @dev return current pool balance.
     *
     */
    function viewRewardPoolBalance() public view returns (uint) {
        return rewardPoolBal;
    }

    /**
     * @dev returns the number of stake instances tied to a wallet.
     */
    function numberOfStakeInstances() public view returns (uint256) {
        return activeStake[msg.sender];
    }

    /**
     * @dev returns current rewards for given stake instance
     */
    function currentRewards(
        address user,
        uint256 _stakeid
    ) public view returns (uint) {
        require(_stakeid >= 0, "Please set valid stakeid!");
        require(activeStake[user] < _stakeid, "Stake instance does not exist");
        require(
            staking[user][_stakeid]._amount > 0,
            "Stake instance does not exist"
        );
        uint256 currentTime = block.timestamp;
        uint256 rewards = 0;
        uint256 locktime = staking[user][_stakeid]._startTime + oneMonth;
        uint256 oneWeekLocktime = staking[user][_stakeid]._startTime + oneWeek;
        uint256 userStartTime = staking[user][_stakeid]._startTime;
        uint256 userClaimTime = staking[user][_stakeid]._claimTime;
        uint256 userAmount = staking[user][_stakeid]._amount;
        uint256 userAPY = staking[user][_stakeid]._APY;
        if (currentTime >= locktime) {
            uint256 timeDifference = userClaimTime - userStartTime;
            uint256 alpha = 0;
            uint256 beta = 0;
            if (timeDifference <= oneMonth) {
                alpha = timeDifference;
            } else {
                beta = timeDifference - oneMonth;
            }
            rewards =
                (userAmount *
                    userAPY *
                    ((oneMonth - alpha) +
                        ((currentTime - (locktime + beta)) * 3) /
                        2)) /
                (100 * oneYear);
        } else if (currentTime >= oneWeekLocktime) {
            rewards =
                (userAmount * userAPY * (currentTime - userClaimTime)) /
                (100 * oneYear);
        }
        return rewards;
    }

    /**
     * @dev stake amount for particular duration.
     * parameters : _stakeamount ( need to set token amount for stake)
     * it will increase activeStake result of particular wallet.
     */
    function stake(uint256 _stakeamount) public returns (bool) {
        address user = msg.sender;
        require(
            TokenI(tokenAddress).balanceOf(user) >= _stakeamount,
            "Insufficient tokens"
        );
        require(_stakeamount > 0, "Amount should be greater than 0");
        _stakeamount = _stakeamount * 10 ** 18;
        staking[user][activeStake[user]] = _staking(
            activeStake[user],
            block.timestamp,
            block.timestamp,
            _stakeamount,
            APY
        );
        TokenI(tokenAddress).transferFrom(user, address(this), _stakeamount);
        activeStake[user] = activeStake[user] + 1;
        emit StakeEvent(activeStake[user], address(this), _stakeamount);
        return true;
    }

    /**
     * @dev stake amount release.
     * parameters : _stakeid is active stake ids which is getting from activeStake-1
     *
     * it will decrease activeStake result of particular wallet.
     * result : If unstake happen before time duration it will set 50% penalty on profited amount else it will sent you all stake amount,
     *          to the staking wallet.
     */
    function unstake(uint256 _stakeid) public returns (bool) {
        address user = msg.sender;
        require(
            staking[user][_stakeid]._amount > 0,
            "Stake instance does not exist!"
        );
        require(_stakeid > 0, "Please set valid stakeid!");
        uint256 userAmount = staking[user][_stakeid]._amount;
        uint256 withdrawAmount = viewWithdrawAmount(_stakeid);
        if (withdrawAmount >= userAmount) {
            _updateRewards(withdrawAmount - userAmount, true);
        } else {
            _updateRewards(userAmount - withdrawAmount, false);
        }

        activeStake[user] = activeStake[user] - 1;
        lastStake = activeStake[user];

        staking[user][_stakeid]._id = staking[user][lastStake]._id;
        staking[user][_stakeid]._amount = staking[user][lastStake]._amount;
        staking[user][_stakeid]._startTime = staking[user][lastStake]
            ._startTime;
        staking[user][_stakeid]._claimTime = staking[user][lastStake]
            ._claimTime;
        staking[user][_stakeid]._APY = staking[user][lastStake]._APY;

        staking[user][lastStake]._id = 0;
        staking[user][lastStake]._amount = 0;
        staking[user][lastStake]._startTime = 0;
        staking[user][lastStake]._claimTime = 0;
        staking[user][_stakeid]._APY = 0;

        TokenI(tokenAddress).transfer(user, withdrawAmount);
        emit Unstake(_stakeid, user, withdrawAmount);

        return true;
    }

    /**
     * @dev claims accrued rewards
     */

    function claim(uint256 _stakeid) public returns (bool) {
        address user = msg.sender;
        require(_stakeid >= 0, "Please set valid stakeid!");
        require(activeStake[user] <= _stakeid, "Stake instance does not exist");
        require(
            staking[user][_stakeid]._amount > 0,
            "Stake instance does not exist"
        );
        uint256 rewards = currentRewards(user, _stakeid);
        require(rewards > 0, "Cannot claim non zero amount");
        TokenI(tokenAddress).transfer(user, rewards);
        staking[user][_stakeid]._claimTime = block.timestamp;
        emit Claim(_stakeid, user, rewards);
        return true;
    }

    /**
     * @dev To know total withdrawal stake amount
     * parameters : _stakeid is active stake ids which is getting from activeStake-
     */
    function viewWithdrawAmount(
        uint256 _stakeid
    ) public view returns (uint256) {
        address user = msg.sender;
        uint256 currentTime = block.timestamp;
        uint256 startTime = staking[user][_stakeid]._startTime;
        uint256 locktime = startTime + oneMonth;
        uint256 oneWeekLocktime = startTime + oneWeek;
        uint256 twoWeekLocktime = startTime + oneWeek * 2;
        uint256 threeWeekLocktime = startTime + oneWeek * 3;
        uint256 penalty = (staking[user][_stakeid]._amount * 5) / 100;
        uint256 userAmount = staking[user][_stakeid]._amount;
        uint256 userRewards = currentRewards(user, _stakeid);
        uint256 withdrawAmount = userAmount;
        uint256 poolModifier = 0;
        bool isPositive = true;
        require(userAmount > 0, "Stake instance does not exist!");
        require(_stakeid >= 0, "Please set valid stakeid!");

        if (currentTime < oneWeekLocktime) {
            poolModifier += penalty;
            isPositive = false;
        } else if (currentTime < twoWeekLocktime) {
            poolModifier += (userRewards * 25) / 100;
        } else if (currentTime < threeWeekLocktime) {
            poolModifier += (userRewards * 35) / 100;
        } else if (currentTime < locktime) {
            poolModifier += (userRewards * 40) / 100;
        } else {
            poolModifier += userRewards;
        }
        if (isPositive) {
            withdrawAmount += poolModifier;
        } else {
            withdrawAmount -= poolModifier;
        }
        return withdrawAmount;
    }

    /**
     * @dev To know Penalty amount, if you unstake before locktime
     * parameters : _stakeid is active stake ids which is getting from activeStake-
     */
    function viewPenalty(uint256 _stakeid) public view returns (uint256) {
        address user = msg.sender;
        uint256 penaltyTime = staking[user][_stakeid]._startTime + oneWeek;
        uint256 penalty = 0;
        require(
            staking[user][_stakeid]._amount > 0,
            "Wallet instance does not exist"
        );
        if (block.timestamp < penaltyTime) {
            penalty = (staking[user][_stakeid]._amount * 5) / 100;
        }
        return penalty;
    }
}
