// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract Airdrop is Ownable {
    using SafeERC20 for IERC20;

    mapping(uint256 => mapping(address => bool)) public _airdropMap;
    mapping(uint256 => bool) private _nonces;
    address private _signer;

    constructor(address signer) {
        _signer = signer;
    }

    function batchSendFt(address token,address[] memory to,uint256[] memory amounts) external onlyOwner{
        for (uint i=0;i<to.length;i++){
            IERC20(token).safeTransferFrom(msg.sender, to[i], amounts[i]);
        }       
    }

    function batchSend(address token,address[] memory to,uint256[] memory amounts,uint256 decimals) external onlyOwner{
        for (uint i=0;i<to.length;i++){
            IERC20(token).safeTransferFrom(msg.sender, to[i], amounts[i] * 10**decimals);
        }  
    }   

    function takeFt(uint issue,address token, uint256 amount, uint256 nonce, bytes memory signature) external {
        require(!_airdropMap[issue][msg.sender], "error!");
        _verify(nonce,signature,abi.encodePacked(msg.sender,issue, token, amount, nonce));
        _airdropMap[issue][msg.sender] = true;
        IERC20(token).safeTransferFrom(address(this), msg.sender, amount);
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