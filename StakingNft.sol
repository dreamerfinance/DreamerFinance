// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";


contract StakingNft is ReentrancyGuard,ERC165,IERC721Receiver,Ownable {
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
        uint256 nftType;
    }

    struct User {
        uint256 stakes;
        uint256 accUP;
        uint256 cache;       
        uint256 got;
        uint256[] tokenIds;
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
    
    event Stake(address indexed user,address indexed token, uint256 nftId, uint256 nftType);
    event Redeem(address indexed user,address indexed token, uint256 nftId,address awardToken,uint256 awardAmount, uint256 nftType);
    event Reward(address indexed user,address indexed token, uint256 amount);
    
    constructor(
        address award,
        uint256 total,
        uint period,
        uint256 startBlock,
        string[] memory names,
        address[] memory stakings,
        uint256[] memory rates,
        uint256[] memory nftType
        ) {
        _award = award;
        _total = total;     
        _period = period;
        _startblock = startBlock;
        _endblock = startBlock + 28800 * period;
        _perBlockAward = total.div(28800 * period);

        for (uint i = 0; i < stakings.length; i ++) {
            _stakings.push(stakings[i]);
            _pools[stakings[i]].name = names[i]; 
            _pools[stakings[i]].token = stakings[i];
            _pools[stakings[i]].rate = rates[i];
            _pools[stakings[i]].flag = true;
            _pools[stakings[i]].nftType = nftType[i];
        }
        
    }

    function stakeBy721(address nftToken, uint256 tokenId) public nonReentrant {
        require(block.number >= _startblock && block.number <= _endblock, "requires block");
        Pool storage pool = _pools[nftToken];
        require(pool.flag, "pool not exists");
        uint256 accUP = _nowAccUP(pool);
        User storage user = _users[nftToken][msg.sender];
        user.cache += (user.stakes * (accUP - user.accUP)) / 10**32;
        user.stakes += 1;
        user.accUP = accUP;
        pool.totalStakes += 1;
        pool.accUP = accUP;
        pool.last = block.number;
        user.tokenIds.push(tokenId);
        IERC721(nftToken).transferFrom(msg.sender,address(this),tokenId);
        emit Stake(msg.sender,nftToken,tokenId,721); 
    }

    function stakeBy1155(address nftToken, uint256 tokenId) public nonReentrant {
        require(block.number >= _startblock && block.number <= _endblock, "requires block");
        Pool storage pool = _pools[nftToken];
        require(pool.flag, "pool not exists");
        uint256 accUP = _nowAccUP(pool);
        User storage user = _users[nftToken][msg.sender];
        user.cache += (user.stakes * (accUP - user.accUP)) / 10**32;
        user.stakes += 1;
        user.accUP = accUP;

        pool.totalStakes += 1;
        pool.accUP = accUP;
        pool.last = block.number;
        user.tokenIds.push(tokenId);
        IERC1155(nftToken).safeTransferFrom(
            msg.sender,
            address(this),
            tokenId,
            1,
            ""
        );
        emit Stake(msg.sender,nftToken,tokenId,1155); 
    }

    function getUser(address nftToken, address account)
        public
        view
        returns (
            uint256 stakes,
            uint256 got,
            uint256 newReward
        )
    {
        User storage user = _users[nftToken][account];
        Pool storage pool = _pools[nftToken];
        stakes = user.stakes;
        got = user.got;
        newReward = _emergency
            ? 0
            : (user.stakes * (_nowAccUP(pool) - user.accUP)) /
                10**32 +
                user.cache;
    }

    function _nowAccUP(Pool storage pool) private view returns (uint256) {
        if (pool.totalStakes == 0) {
            return 0;
        }
        uint256 last = pool.last;
        uint256 profit = (block.number - last) * _perBlockAward * pool.rate / 100 ;
        return pool.accUP + (profit * 10**32) / pool.totalStakes;
    }

    function reward(address nftToken) public nonReentrant {
        require(!_emergency, "in emergency");

        User storage user = _users[nftToken][msg.sender];
        Pool storage pool = _pools[nftToken];
        require(pool.flag, "pool not exists");
        uint256 accUP = _nowAccUP(pool);
        uint256 amount =
            (user.stakes * (accUP - user.accUP)) / 10**32 + user.cache;
        require(amount > 0, "no reward");

        user.got += amount;
        user.cache = 0;
        user.accUP = accUP;

        pool.accUP = accUP;
        pool.last = block.number;
        IERC20(_award).safeTransfer(msg.sender, amount);
        emit Reward(msg.sender,_award,amount);
    }

    function redeemBy721(address nftToken) public nonReentrant {
        User storage user = _users[nftToken][msg.sender];
        require(user.stakes > 0, "no stake");

        Pool storage pool = _pools[nftToken];
        require(pool.flag, "pool not exists");

        uint256 amount;
        if (!_emergency) {
            uint256 accUP = _nowAccUP(pool);

            amount =
                (user.stakes * (accUP - user.accUP)) / 10**32 + user.cache;
            if (amount > 0) {
                IERC20(_award).safeTransfer(msg.sender, amount);
            }
            pool.accUP = accUP;
            pool.last = block.number;
        }

        pool.totalStakes -= user.stakes;
        for (uint i = 0; i < user.tokenIds.length; i++){
            delete user.tokenIds[i];
            IERC721(nftToken).transferFrom(address(this),msg.sender,user.tokenIds[i]);
            emit Redeem(msg.sender,nftToken,user.tokenIds[i],_award,amount,721);
        }
        delete user.tokenIds;  

    }

    function redeemBy1155(address nftToken) public nonReentrant {
        User storage user = _users[nftToken][msg.sender];
        require(user.stakes > 0, "no stake");

        Pool storage pool = _pools[nftToken];
        require(pool.flag, "pool not exists");

        uint256 amount;
        if (!_emergency) {
            uint256 accUP = _nowAccUP(pool);

            amount =
                (user.stakes * (accUP - user.accUP)) / 10**32 + user.cache;
            if (amount > 0) {
                IERC20(_award).safeTransfer(msg.sender, amount);
            }
            pool.accUP = accUP;
            pool.last = block.number;
        }

        pool.totalStakes -= user.stakes;
        for (uint i = 0; i < user.tokenIds.length; i++) {
            IERC1155(nftToken).safeTransferFrom(
                address(this),
                msg.sender,         
                user.tokenIds[i],
                1,
                ""
            );
            emit Redeem(msg.sender,nftToken,user.tokenIds[i],_award,amount,1155);
        }
        delete user.tokenIds;      
    }

    function setEmergency(bool value) public onlyOwner {
        _emergency = value;
    }

    function getEmergency() public view returns (bool) {
        return _emergency;
    }



    /*
     * implements IERC1155Receiver.onERC1155Received()
     */
    function onERC1155Received(
        address operator,
        address from,
        uint256 id,
        uint256 value,
        bytes calldata data
    ) external returns (bytes4) {
        return
            bytes4(
                keccak256(
                    "onERC1155Received(address,address,uint256,uint256,bytes)"
                )
            );
    }

    /*
     * implements IERC1155Receiver.onERC1155BatchReceived()
     */
    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata values,
        bytes calldata data
    ) external returns (bytes4) {
        return
            bytes4(
                keccak256(
                    "onERC1155BatchReceived(address,address,uint256[],uint256[],bytes)"
                )
            );
    }

    function onERC721Received(
        address operator,
        address from,
        uint256 tokenId,
        bytes calldata data
    ) external returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}