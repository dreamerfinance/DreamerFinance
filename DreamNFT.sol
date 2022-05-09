// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract DreamNFT is ERC1155, Ownable {

    address private _signer;
    address private _treasury;
    mapping(address => uint) public _addrNonces;
    mapping(uint256 => bool) private _nonces;
    uint256 private _idCounter;
    // 1: FT, 2: NFT
    mapping(uint256 => uint8) private _kindTypes;
    mapping(uint256 => uint256) private _tokenToKind;
    mapping(uint256 => uint256) private _kindAmounts;

    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9; 

    event Success(uint256 nonce);

    constructor(address treasury, address signer) public ERC1155("https://gateway.pinata.cloud/ipfs/QmVzTErJP9Wzsmd6LWJbBzvwua1xoUWwZPq63N6vSgKZNq/{id}.json") {
        _treasury = treasury;
        _signer = signer;
    }

    function setURI(string memory newuri) external onlyOwner {
        _setURI(newuri);
    }

    function setSigner(address signer) external onlyOwner {
        _signer = signer;
    }

    function setTreasury(address treasury) external onlyOwner {
        _treasury = treasury;
    }

    function getInfo()
        external
        view
        returns (
            address,
            address
        )
    {
        return (_treasury, _signer);
    }

    function addKindTypes(uint256[] memory kinds, uint8[] memory types)
        external
        onlyOwner
    {
        require(kinds.length == types.length);

        for (uint256 i = 0; i < kinds.length; i++) {
            uint256 kind = kinds[i];
            uint8 type_ = types[i];
            require(
                kind <= 10000 &&
                    _kindTypes[kind] == 0 &&
                    (type_ == 1 || type_ == 2)
            );

            _kindTypes[kind] = type_;
            if (type_ == 1) {
                _tokenToKind[kind] = kind;
            }
        }
    }

    function getKindType(uint256 kind) external view returns (uint8) {
        return _kindTypes[kind];
    }

    function _charge(address token, uint256 amount, address to) internal {
        require(
                IERC20(token).transferFrom(msg.sender, to, amount),
                "fails to transfer token"
            ); 
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

        emit Success(nonce);
    }

    function _verifyBatch(
        uint256[] memory nonces,
        bytes memory signature,
        bytes memory packed
    ) internal {
        // this recreates the message that was signed on the client
        bytes32 message = ECDSA.toEthSignedMessageHash(keccak256(packed));
        address signer = ECDSA.recover(message, signature);
        require(signer == _signer, "signature invalid");

        for (uint256 i = 0; i < nonces.length; i++) {
            uint256 nonce = nonces[i];
            require(!_nonces[nonce], "nonce not available");
            _nonces[nonce] = true;

            emit Success(nonce);
        }
    }

    function _mintFungible(
        address to,
        uint256 kind,
        uint256 amount
    ) internal {
        require(_kindTypes[kind] == 1, "kind not FT");
        _mint(to, kind, amount, "");
        _kindAmounts[kind] += amount;
    }

    function _mintNonFungible(address to, uint256 kind)
        internal
        returns (uint256)
    {
        require(_kindTypes[kind] == 2, "kind not NFT");

        _idCounter += 1;
        _mint(to, _idCounter, 1, "");
        _tokenToKind[_idCounter] = kind;
        _kindAmounts[kind] += 1;

        return _idCounter;
    }

    function mintFungible(
        address to,
        uint256 kind,
        uint256 amount,
        address coin,
        uint256 coinAmount,
        uint256 nonce,
        bytes memory signature
    ) external {
        _verify(
            nonce,
            signature,
            abi.encodePacked(to, kind, amount, coin, coinAmount, nonce)
        );

        if (coinAmount > 0) {
            _charge(coin, coinAmount, _treasury);
        }

        _mintFungible(to, kind, amount);
    }

    function mintNonFungibles(
        address to,
        address grouper,
        uint256[] memory kinds,
        uint256[] memory limits,
        address coin,
        uint256 coinAmount,
        uint256 nonce,
        bytes memory signature
    ) external {
        require(kinds.length == limits.length);
        _verify(
            nonce,
            signature,
            abi.encodePacked(to, kinds, limits, coin, coinAmount, nonce)
        );

        if (coinAmount > 0 && grouper == address(0)) {
            _charge(coin, coinAmount, _treasury);
        }else if (coinAmount > 0 && grouper != address(0)){
            uint256 groupAmount = coinAmount / 2;
            _charge(coin, groupAmount, grouper);
            _charge(coin, coinAmount - groupAmount, _treasury);
        }

        for (uint256 i = 0; i < kinds.length; i++) {
            require(_kindAmounts[kinds[i]] < limits[i], "limit exceeded");
            _mintNonFungible(to, kinds[i]);
        }
    }

    function permit(address owner, address spender, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        require(deadline >= block.timestamp, 'DreamNFT: EXPIRED');
        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19Ethereum Signed Message:\n32',
                keccak256(
                    abi.encodePacked(
                        '\x19\x01',
                        keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, _addrNonces[owner]++, deadline))
                    )
                )
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, 'DreamNFT: INVALID_SIGNATURE');
        _setApprovalForAll(owner, spender, true);
    }

    function airDropNonFungible(uint256 kind, address[] memory accounts)
        external
        onlyOwner
    {
        require(_kindTypes[kind] == 2, "kind not NFT");

        for (uint256 i = 0; i < accounts.length; i++) {
            _idCounter += 1;
            _mint(accounts[i], _idCounter, 1, "");
            _tokenToKind[_idCounter] = kind;
        }
        _kindAmounts[kind] += accounts.length;
    }

}