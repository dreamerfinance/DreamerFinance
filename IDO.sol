// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract IDO is Ownable,ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    mapping(uint256 => bool) private _nonces;

    address public _quoteToken;
    address public _idoToken;
    
    address private _idoer;
    address private _signer;
    uint256[3] public _points;
    uint256[3] public _amounts;
    uint256[4] public _gear;
    uint private _currRound;
    bool private _success;
    uint256 private _idoAmount;
    uint256 private _totalIdo;
    mapping(address => mapping(uint => bool)) public _limit;
    uint256 private _joiners;

    event Ido(address indexed user,address indexed token, uint256 amount, address indexed quoteToken, uint256 quoteAmount, uint256 price, uint currRound, uint256 nonce);
    
    constructor(address quoteToken,address idoToken,address idoer,address signer) {
        _quoteToken = quoteToken;
        _idoToken = idoToken;
        _currRound = 1;
        _totalIdo = 7000000 * 10**18;
        _idoer = idoer;
        _signer = signer;
        _points = [250,275,300];
        _amounts = [1000000*10**18,2000000*10**18,4000000*10**18];
        _gear = [100,200,300,400];        
    }

    function getCurrRound() public view returns (uint) {
        return _currRound;
    }

    function getCurrPrice() public view returns (uint256) {
        return _points[_currRound - 1] * 10**18 / 1000;
    }

    function gearList() public view returns (uint256[4] memory) {
        uint256[4] memory gear = _gear;
        return gear;
    }

    function roundAmount() public view returns (uint256) {
        return _amounts[_currRound - 1];
    }

    function idoAmount() public view returns (uint256) {
        return _idoAmount;
    }

    function setSigner(address signer) external onlyOwner {
        _signer = signer;
    }

    function getInfto() external view returns (uint256, uint256, uint256, uint, uint256) {
        return (_totalIdo, _idoAmount, _joiners, _currRound, getCurrPrice());
    }

    function ido(uint256 gearIndex) external nonReentrant {
        require(_currRound == 3,'Ido currRound err!');
        require(!_success,'ido is end!');
        require(gearIndex <= 3 && gearIndex >= 0,'gearIndex is err!');
        require(!_limit[msg.sender][_currRound],'ido is limit 1 times!'); 
        uint256 price = getCurrPrice();               
        uint256 quoteAmount = price.mul(_gear[gearIndex]); 
        uint256 idoValue = _gear[gearIndex] * 10**18; 
        _idoAmount = _idoAmount.add(idoValue);
        require(_idoAmount <= _totalIdo ,'ido is end');
        if (_idoAmount == _totalIdo) {
            _success = true;
        }
        _limit[msg.sender][_currRound] = true;
        if (!_limit[msg.sender][1]&&!_limit[msg.sender][2]){
            _joiners ++;
        }       
        IERC20(_quoteToken).safeTransferFrom(msg.sender, _idoer, quoteAmount);
        IERC20(_idoToken).safeTransfer(msg.sender, idoValue);
        emit Ido(msg.sender,_idoToken, idoValue, _quoteToken, quoteAmount, price, _currRound, 0);
    }

    function idoLimit(address to,uint256 gearIndex,uint256 deadline,uint256 nonce,bytes memory signature) external nonReentrant  {
        require(msg.sender == to,'Ido sender err!');
        require(_currRound < 3,'Ido currRound err!');
        require(gearIndex <= 3 && gearIndex >= 0,'gearIndex is err!');
        require(!_limit[msg.sender][_currRound],'ido is limit 1 times!');     
        _verify(nonce,signature,abi.encodePacked(to, gearIndex,deadline, nonce)); 
        uint256 price = getCurrPrice();               
        uint256 quoteAmount = price.mul(_gear[gearIndex]); 
        uint256 idoValue = _gear[gearIndex] * 10**18; 
        _idoAmount = _idoAmount.add(idoValue);
        if (_idoAmount >= _amounts[0].add(_amounts[1]) && _currRound == 2) {
            _currRound = 3;
        }else if (_idoAmount >= _amounts[0] && _currRound == 1){
            _currRound = 2;
        }
        if (_limit[msg.sender][1]) {
            _joiners ++;
        }
        _limit[msg.sender][_currRound] = true;       
        IERC20(_quoteToken).safeTransferFrom(msg.sender, _idoer, quoteAmount);
        IERC20(_idoToken).safeTransfer(msg.sender, idoValue);
        emit Ido(msg.sender,_idoToken, idoValue, _quoteToken, quoteAmount, price, _currRound, nonce);
    }

    function setSuccess() external onlyOwner {
        require(_success,'ido is end!');
        _success = true;
    }

    function _verify(
        uint256 nonce,
        bytes memory signature,
        bytes memory packed
    ) internal {
        // this recreates the message that was signed on the client
        bytes32 message = ECDSA.toEthSignedMessageHash(keccak256(packed));
        address signer = ECDSA.recover(message, signature);
        require(signer == _signer, "signature invalid");
        require(!_nonces[nonce], "nonce not available");
        _nonces[nonce] = true;
    }

}