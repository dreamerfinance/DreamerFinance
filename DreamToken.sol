// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.5.0) (token/ERC20/ERC20.sol)

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract DreamToken is Ownable, IERC20, IERC20Metadata {
    using SafeMath for uint256;
    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    bytes32 private constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping(address => uint) private nonces;
    mapping(address => bool) private _fwList; //from while list
    mapping(address => bool) private _tbList; //to black list
    mapping(uint256 => bool) private _nonces;
    address private _signer;
    address public _taxer;
    address public _mTaxer;
    address public _sTaxer;
    uint8 private _taxFeeRate;
    uint256 private _mTotalSupply;
    uint256 private _mSurplus;
    uint256 private _mUsed;
    uint256 public _startM;
    bool public _isMining;
    mapping(uint => uint256) public _mLimit;
    mapping(address => uint256) public _uM;
    event Mining(address indexed user, uint256 amount, uint256 fee, uint256 nonce);

    constructor(string memory name_, string memory symbol_, address signer_, address taxer_, address mTaxer_, address sTaxer_) {
        _name = name_;
        _symbol = symbol_;
        _signer = signer_;
        _taxer = taxer_;
        _taxFeeRate = 10;
        _mTaxer = mTaxer_;
        _sTaxer = sTaxer_;
        _mTotalSupply = 990000000 * 10 ** uint(decimals());
        _mSurplus = 990000000 * 10 ** uint(decimals());        
        _mint(msg.sender, 10000000 * 10 ** uint(decimals()));
    }

    function setStartMining(uint256 startBlock) external onlyOwner {
        _startM = startBlock;
        _isMining = true;
    }

    function setMonthLimit(uint[] memory months,uint256[] memory amounts) external onlyOwner {
        require(months.length == amounts.length, 'Parma err!');
        for (uint i = 0; i < months.length; i++){
            _mLimit[months[i]] = amounts[i];
        }
    }

    function getMonthLimit(uint month) public view returns (uint256){
        return _mLimit[month] * 10**18;
    }

    function getNonces(address owner) public view returns (uint) {
        return nonces[owner];
    }

    function miningTotalSupply() public view returns (uint256) {
        return _mTotalSupply;
    }

    function miningSurplus() public view returns (uint256) {
        return _mSurplus;
    }

    function miningUsed() public view returns (uint256) {
        return _mUsed;
    }

    function setSigner(address signer) external onlyOwner {
        _signer = signer;
    }

    function setTaxer(address taxer) external onlyOwner {
        _taxer = taxer;
    }

    function setmTaxer(address mTaxer) external onlyOwner {
        _mTaxer = mTaxer;
    }

    function setsTaxer(address sTaxer) external onlyOwner {
        _sTaxer = sTaxer;
    }

    function setFwList(address[] memory fs_) external onlyOwner {
        for (uint i = 0; i <fs_.length; i++) {
            _fwList[fs_[i]] = true;
        }
    }

    function setTbList(address[] memory tb_) external onlyOwner {
        for (uint i = 0; i <tb_.length; i++) {
            _tbList[tb_[i]] = true;
        }
    }

    function cancelFw(address fs_) external onlyOwner {
        _fwList[fs_] = false;
    }

    function cancelTb(address tb_) external onlyOwner {
        _tbList[tb_] = false;
    }

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external {
        require(deadline >= block.timestamp, 'Dream Token: EXPIRED');
        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19Ethereum Signed Message:\n32',
                keccak256(
                    abi.encodePacked(
                        '\x19\x01',
                        keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
                    )
                )
            )
        );
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, 'Dream Token: INVALID_SIGNATURE');
        _approve(owner, spender, value);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender,amount);
    }

    function mint(address to, uint256 amount, uint256 day, uint256 nonce, bytes memory signature) external {
        require(_isMining,'Mining no start!');
        require(block.number > _startM,'Mining no start!');
        require(day > _uM[to], 'This day is already taked!'); 
        require(_mUsed.add(amount) <= _mTotalSupply,'MiningTotalSupply limit!');
        uint month = (block.number - _startM) / (28800 * 30);
        uint p = (block.number - _startM) % (28800 * 30) + 1;
        uint limit = p * (_mLimit[month+1] - _mLimit[month]) * 10**18 / 30;
        require(_mUsed.add(amount) <= limit ,'Mining limit!');             
        _verify(nonce,signature,abi.encodePacked(to, amount, day, nonce)); 
        _uM[to] = day;
        _mSurplus = _mSurplus.sub(amount);
        _mUsed = _mUsed.add(amount);
        uint256 fee;
        uint256 mFee;
        if (to == _taxer || to == _mTaxer) {
            _mint(to,amount);
        }else{
            mFee = amount / 20;
            fee = mFee * 2;
            _mint(_taxer,mFee);
            _mint(_mTaxer,mFee);
            _mint(to,amount.sub(fee));
        }        
        emit Mining(to, amount, fee, nonce);
    }

    function _transferTax(
        address from,
        address to,
        uint256 amount
    ) internal virtual {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(from, to, amount);
        uint256 takeFee = amount.div(_taxFeeRate);
        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount , "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[from] = fromBalance - amount ;
        }
        uint256 toAmount = amount - takeFee;
        _balances[_sTaxer] += takeFee;
        _balances[to] += toAmount;

        emit Transfer(from, _sTaxer, takeFee);
        emit Transfer(from, to, toAmount);

        _afterTokenTransfer(from, to, amount);
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

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        if (_fwList[owner] || !_tbList[to]){
            _transfer(owner, to, amount);
        }else{
            _transferTax(owner, to, amount);
        } 
        return true;
    }

    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, amount);
        return true;
    }

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        if (_fwList[from] || !_tbList[to]){
          _transfer(from, to, amount);
        }else{
          _transferTax(from, to, amount);
        }
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, allowance(owner, spender) + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        address owner = _msgSender();
        uint256 currentAllowance = allowance(owner, spender);
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(owner, spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(from, to, amount);

        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[from] = fromBalance - amount;
        }
        _balances[to] += amount;

        emit Transfer(from, to, amount);

        _afterTokenTransfer(from, to, amount);
    }

    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);

        _afterTokenTransfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
        }
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);

        _afterTokenTransfer(account, address(0), amount);
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _spendAllowance(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}

    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}
}
