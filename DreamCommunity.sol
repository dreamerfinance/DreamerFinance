// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

interface IEIP2612 is IERC20 {
  function DOMAIN_SEPARATOR() external view returns (bytes32);
  function nonces(address owner) external view returns (uint256);
  function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;
}

contract DreamCommunity is ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    struct Direct {
        address direct;
        bool isUsed;
    }

    mapping(address => Direct) private _relation;   
    address public _token;
    uint256 public _amount;

    event Community(address indexed user,address indexed to, uint256 amount);

    constructor(address token,uint256 amount) {
        _token = token;
        _amount = amount;
    }

    function getRelation(address user) public view returns (address) {
        return _relation[user].direct;
    }

    function communityWithPermit(address to,uint256 amount, uint deadline, uint8 v, bytes32 r, bytes32 s) external nonReentrant {
        require(!_relation[to].isUsed,'check err!');
        _relation[to].direct = msg.sender;
        _relation[to].isUsed = true;
        if (!_relation[msg.sender].isUsed) {
            _relation[msg.sender].direct = address(0);
            _relation[msg.sender].isUsed = true;
        }
        // permit
        IEIP2612(_token).permit(msg.sender, address(this), amount, deadline, v, r, s);
        IERC20(_token).safeTransferFrom(msg.sender, to, amount);
        emit Community(msg.sender, to, amount);
    }

    function community(address to) external nonReentrant {
        require(!_relation[to].isUsed,'check err!');
        _relation[to].direct = msg.sender;
        _relation[to].isUsed = true;
        if (!_relation[msg.sender].isUsed) {
            _relation[msg.sender].direct = address(0);
            _relation[msg.sender].isUsed = true;
        }
        IERC20(_token).safeTransferFrom(msg.sender, to, _amount);
        emit Community(msg.sender, to, _amount);
    }

}