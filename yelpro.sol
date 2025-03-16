// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v3.4.0/contracts/math/SafeMath.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v3.4.0/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v3.4.0/contracts/token/ERC20/ERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v3.4.0/contracts/token/ERC20/ERC20Burnable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v3.4.0/contracts/GSN/Context.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v3.4.0/contracts/access/Ownable.sol";

contract Yelpro is ERC20Burnable, Ownable {
  using SafeMath for uint256;

  mapping(address => bool) public isExcludedFromFee;
  mapping(address => bool) public isMinter;
  mapping(address => bool) public whiteListedPair;

  uint256 public immutable MAX_SUPPLY;
  uint256 public BUY_FEE = 0;
  uint256 public SELL_FEE = 0;
  uint256 public TREASURY_FEE = 100;

  uint256 public totalBurned = 0;

  address payable public poolAddress;

  event TokenRecoverd(address indexed _user, uint256 _amount);
  event FeeUpdated(address indexed _user, uint256 _feeType, uint256 _fee);
  event ToggleV2Pair(address indexed _user, address indexed _pair, bool _flag);
  event AddressExcluded(address indexed _user, address indexed _account, bool _flag);
  event MinterRoleAssigned(address indexed _user, address indexed _account);
  event MinterRoleRevoked(address indexed _user, address indexed _account);

  constructor(
    uint256 _maxSupply,
    uint256 _initialSupply,
    address payable _poolAddress
  ) public ERC20("Yelpro", "Yelp") {
    require(_initialSupply <= _maxSupply, "Yelpro: The _initialSupply should not exceed the _maxSupply");

    MAX_SUPPLY = _maxSupply;
    poolAddress = _poolAddress;

    isExcludedFromFee[owner()] = true;
    isExcludedFromFee[address(this)] = true;
    isExcludedFromFee[poolAddress] = true;

    if (_initialSupply > 0) {
      _mint(_msgSender(), _initialSupply);
    }
  }

  modifier onlyDev() {
    require(poolAddress == _msgSender() || owner() == _msgSender(), "Yelpro: You don't have the permission!");
    _;
  }

  modifier hasMinterRole() {
    require(isMinter[_msgSender()], "Yelpro: You don't have the permission!");
    _;
  }

  function _burn(address account, uint256 amount) internal override {
    super._burn(account, amount);
    totalBurned = totalBurned.add(amount);
  }

  event TradingEnabled(bool tradingEnabled);

  bool public tradingEnabled;

  function enableTrading() external onlyDev{
      require(!tradingEnabled, "Yelpro: Trading already enabled.");
      tradingEnabled = true;

      emit TradingEnabled(tradingEnabled);
  }

  function _transfer(
    address sender,
    address recipient,
    uint256 amount
  ) internal override {
    require(sender != address(0), "ERC20: transfer from the zero address");
    require(recipient != address(0), "ERC20: transfer to the zero address");
    require(tradingEnabled || isExcludedFromFee[sender] || isExcludedFromFee[recipient], "Yelpro: Trading not yet enabled!");

    uint256 burnFee;
    uint256 treasuryFee;

    if (whiteListedPair[sender]) {
      burnFee = BUY_FEE;
    } else if (whiteListedPair[recipient]) {
      burnFee = SELL_FEE;
      treasuryFee = TREASURY_FEE;
    }

    if (
      (isExcludedFromFee[sender] || isExcludedFromFee[recipient]) ||
      (!whiteListedPair[sender] && !whiteListedPair[recipient])
    ) {
      burnFee = 0;
      treasuryFee = 0;
    }

    uint256 burnFeeAmount = amount.mul(burnFee).div(10000);
    uint256 treasuryFeeAmount = amount.mul(treasuryFee).div(10000);

    if (burnFeeAmount > 0) {
      _burn(sender, burnFeeAmount);
      amount = amount.sub(burnFeeAmount);
    }

    if (treasuryFeeAmount > 0) {
      super._transfer(sender, poolAddress, treasuryFeeAmount);

      amount = amount.sub(treasuryFeeAmount);
    }

    super._transfer(sender, recipient, amount);
  }

  function mint(address _user, uint256 _amount) external hasMinterRole {
    uint256 _totalSupply = totalSupply();
    require(_totalSupply.add(_amount) <= MAX_SUPPLY, "Yelpro: No more minting allowed!");

    _mint(_user, _amount);
  }

  function assignMinterRole(address _account) public onlyOwner {
    isMinter[_account] = true;

    emit MinterRoleAssigned(_msgSender(), _account);
  }

  function revokeMinterRole(address _account) public onlyOwner {
    isMinter[_account] = false;

    emit MinterRoleRevoked(_msgSender(), _account);
  }

  function excludeMultipleAccountsFromFees(address[] calldata _accounts, bool _excluded) external onlyDev {
    for (uint256 i = 0; i < _accounts.length; i++) {
      isExcludedFromFee[_accounts[i]] = _excluded;

      emit AddressExcluded(_msgSender(), _accounts[i], _excluded);
    }
  }

  function enableV2PairFee(address _account, bool _flag) external onlyDev {
    whiteListedPair[_account] = _flag;

    emit ToggleV2Pair(_msgSender(), _account, _flag);
  }

  function updateDevAddress(address payable _poolAddress) external onlyDev {
    require(_poolAddress != address(0), "Can't be the zero address.");
    isExcludedFromFee[poolAddress] = false;
    emit AddressExcluded(_msgSender(), poolAddress, false);

    poolAddress = _poolAddress;
    isExcludedFromFee[poolAddress] = true;

    emit AddressExcluded(_msgSender(), poolAddress, true);
  }

  function updateFee(uint256 feeType, uint256 fee) external onlyDev {
    require(fee <= 900, "Yelpro: The tax Fee cannot exceed 9%");

    // 1 = BUY FEE, 2 = SELL FEE, 3 = TREASURY FEE
    if (feeType == 1) {
      BUY_FEE = fee;
    } else if (feeType == 2) {
      SELL_FEE = fee;
    } else if (feeType == 3) {
      TREASURY_FEE = fee;
    }

    emit FeeUpdated(_msgSender(), feeType, fee);
  }

  function recoverToken(address _token) external onlyDev {
    uint256 tokenBalance = IERC20(_token).balanceOf(address(this));

    require(tokenBalance > 0, "Yelpro: The contract doen't have tokens to be recovered!");

    IERC20(_token).transfer(poolAddress, tokenBalance);

    emit TokenRecoverd(poolAddress, tokenBalance);
  }
}
