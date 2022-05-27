// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract StakingToken is ReentrancyGuard,Ownable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct Pool {
        address token;
        string name;
        uint256 rate;       
        uint256 totalStakes;
        uint256 last;
        uint256 accUP;
        bool flag;
    }

    struct User {
        uint256 stakes;
        uint256 accUP;
        uint256 cache;       
        uint256 got;
    }
   
    address public _award;
    uint256 public _total;
    uint256 public _startblock;
    uint256 public _endblock;
    uint256 public _period;
    uint256 public _perBlockAward;
    bool private _emergency;
    mapping(address => mapping(address => User)) private _users;

    address[] public _stakings;
    mapping(address => mapping(address => uint256)) public _balances;
    mapping(address => Pool) public _pools;
    
    event Stake(address indexed user,address indexed token, uint256 amount);
    event Redeem(address indexed user,address indexed token, uint256 amount,address awardToken,uint256 awardAmount);
    event Reward(address indexed user,address indexed token, uint256 amount);
    
    constructor(
        address award,
        uint256 total,
        uint period,
        uint256 startBlock,
        string[] memory names,
        address[] memory stakings,
        uint256[] memory rates
        ) {
        _award = award;
        _total = total;   
        _period = period;
        _startblock = startBlock;
        _endblock = startBlock + 28800 * period;
        _perBlockAward = total / (28800 * period);

        for (uint i = 0; i < stakings.length; i ++) {
            _stakings.push(stakings[i]);
            _pools[stakings[i]].name = names[i]; 
            _pools[stakings[i]].token = stakings[i];
            _pools[stakings[i]].rate = rates[i];
            _pools[stakings[i]].flag = true;
        }
        
    }

    function stake(address coinToken, uint256 value) public nonReentrant {
        require(block.number >= _startblock && block.number <= _endblock, "requires block");
        require(value > 0, "requires value > 0");

        Pool storage pool = _pools[coinToken];
        require(pool.flag, "pool not exists");

        uint256 accUP = _nowAccUP(pool);
        User storage user = _users[coinToken][msg.sender];
        user.cache += (user.stakes * (accUP - user.accUP)) / 10**18;
        user.stakes += value;
        user.accUP = accUP;

        pool.totalStakes += value;
        pool.accUP = accUP;
        pool.last = block.number;
        IERC20(coinToken).safeTransferFrom(msg.sender, address(this), value);
        emit Stake(msg.sender,coinToken,value);
    }

    function getUser(address coinToken, address account)
        public
        view
        returns (
            uint256 stakes,
            uint256 got,
            uint256 newReward
        )
    {
        User storage user = _users[coinToken][account];
        Pool storage pool = _pools[coinToken];
        stakes = user.stakes;
        got = user.got;
        newReward = _emergency
            ? 0
            : (user.stakes * (_nowAccUP(pool) - user.accUP)) /
                10**18 +
                user.cache;
    }

    function _nowAccUP(Pool storage pool) private view returns (uint256) {
        if (pool.totalStakes == 0) {
            return 0;
        }
        uint256 last = pool.last;
        uint256 profit = (block.number - last) * _perBlockAward * pool.rate / 100 ;
        return pool.accUP + (profit * 10**18) / pool.totalStakes;
    }

    function reward(address coinToken) public nonReentrant {
        require(!_emergency, "in emergency");

        User storage user = _users[coinToken][msg.sender];
        Pool storage pool = _pools[coinToken];
        require(pool.flag, "pool not exists");
        uint256 accUP = _nowAccUP(pool);
        uint256 amount =
            (user.stakes * (accUP - user.accUP)) / 10**18 + user.cache;
        require(amount > 0, "no reward");

        user.got += amount;
        user.cache = 0;
        user.accUP = accUP;

        pool.accUP = accUP;
        pool.last = block.number;
        IERC20(_award).safeTransfer(msg.sender, amount);
        emit Reward(msg.sender,_award,amount);
    }

    function redeem(address coinToken) public nonReentrant {
        User storage user = _users[coinToken][msg.sender];
        require(user.stakes > 0, "no stake");

        Pool storage pool = _pools[coinToken];
        require(pool.flag, "pool not exists");

        uint256 amount;
        if (!_emergency) {
            uint256 accUP = _nowAccUP(pool);

            amount =
                (user.stakes * (accUP - user.accUP)) / 10**18 + user.cache;
            if (amount > 0) {
                IERC20(_award).safeTransfer(msg.sender, amount);
            }
            pool.accUP = accUP;
            pool.last = block.number;
        }

        pool.totalStakes -= user.stakes;

        IERC20(coinToken).safeTransfer(msg.sender, user.stakes);
        emit Redeem(msg.sender,coinToken,user.stakes,_award,amount);
        delete _users[coinToken][msg.sender];
    }

    function setEmergency(bool value) public onlyOwner {
        _emergency = value;
    }

    function getEmergency() public view returns (bool) {
        return _emergency;
    }
    
}