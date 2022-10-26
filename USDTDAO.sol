// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

//modified from BSG
contract USDTDAO is Ownable{
    using SafeMath for uint256; 
    IERC20 public usdt;
    uint256 private constant baseDivider = 10000;
    uint256 private constant freezeDay = 3 days;    //3 days default
    uint256 private constant withdrawDelay = 15 minutes;    //15 minutes default
    uint256 private constant freezeMultiply = 3;
    uint256[5] private packagePrice = [100e18, 500e18, 1000e18, 2000e18, 3000e18]; 
    uint32[5] private packPercent = [100, 100, 100, 200, 300];
    uint32 private constant feePercents = 300;

    address public feeReceivers;
    uint256 public startTime;
    uint256 public totalUser = 1;
    uint256 public totalDeposit;
    uint256 public totalDepositCount;
    uint256 public totalWithdraw;
    uint256 public totalReferWithdraw;
    
    address public defaultRefer;

    struct OrderInfo {
        uint256 start;  //last
        uint256 count;
    }

    mapping(address => OrderInfo[5]) public orderInfos;

    struct UserInfo {
        address referrer;
        uint256 totalDeposit;
        uint256 maxPackPercent;
        uint256 depositCount;
        uint256 withdrawable;
        uint256 recWithdrawable;
        uint256 refReward;
        uint256 recRefReward;
        uint256 lastDeposit;
        address[] downline;
        uint256 up_profit;
    }

    mapping(address=>UserInfo) public userInfo;
    
    event Register(address user, address referral);
    event Deposit(address user, uint256 amount);
    event Withdraw(address user, uint256 withdrawable);
    event WithdrawRef(address user, uint256 amount);

    constructor(address _usdt, address _feeReceivers, address _defaultRefer) {
        usdt = IERC20(_usdt);   
        feeReceivers = _feeReceivers;
        startTime = block.timestamp; 
        defaultRefer = _defaultRefer;
        UserInfo storage user = userInfo[defaultRefer];
        user.referrer = feeReceivers;
    }

    //Get VIEW 
    function getData() external view returns 
        (uint256 _startTime, uint256 _totalUser, uint256 _totalDeposit, uint256 _totalDepositCount, uint256 _totalWithdraw, uint256 _totalReferWithdraw) 
    {
        return (startTime, totalUser, totalDeposit, totalDepositCount, totalWithdraw, totalReferWithdraw);
    }

    function getUserOrderData(address _account) external view returns 
        (uint256 _pack1Start, uint256 _pack2Start, uint256 _pack3Start, uint256 _pack4Start, uint256 _pack5Start) 
    {   
        return (
            orderInfos[_account][0].start,
            orderInfos[_account][1].start,
            orderInfos[_account][2].start,
            orderInfos[_account][3].start,
            orderInfos[_account][4].start
        );
    }

    function getUserDownData(address _account) external view returns 
        (address[] memory _downline, uint256[] memory _profit) 
    {   
        address[] memory downline = new address[](userInfo[_account].downline.length);
        uint256[] memory profit = new uint256[](userInfo[_account].downline.length);

        for(uint256 i = 0; i < userInfo[_account].downline.length; i++){
            downline[i] = userInfo[_account].downline[i];
            profit[i] = userInfo[userInfo[_account].downline[i]].up_profit;
        }

        return (
            downline,
            profit
        );
    }

    //Write External
    function register(address _referral, uint256 _packageID) external {
        require(userInfo[_referral].totalDeposit > 0 || _referral == defaultRefer || _referral != msg.sender, "invalid refer");
        require(userInfo[defaultRefer].totalDeposit > 0 , "invalid refer");
        UserInfo storage user = userInfo[msg.sender];
        require(user.referrer == address(0), "referrer bonded");
        user.referrer = _referral;
        totalUser += 1;
        UserInfo storage user_refer = userInfo[user.referrer];
        user_refer.downline.push(msg.sender);
        deposit(_packageID);
        emit Register(msg.sender, _referral);
    }

    function deposit(uint256 _packageID) public {
        UserInfo storage user = userInfo[msg.sender];
        require(user.referrer != address(0), "register first");
        require(_packageID < 5, "Invalid Package ID");
        require(orderInfos[msg.sender][_packageID].start == 0 || orderInfos[msg.sender][_packageID].start + freezeDay < block.timestamp, "Package Order Freeze");
        
        usdt.transferFrom(msg.sender, address(this), packagePrice[_packageID]);

        UserInfo storage dev = userInfo[feeReceivers];
        dev.withdrawable = packagePrice[_packageID]* uint256(feePercents) / baseDivider;

        OrderInfo storage order = orderInfos[msg.sender][_packageID];

        if(order.start != 0)
            user.withdrawable += packagePrice[_packageID] + ((packagePrice[_packageID] * freezeMultiply * uint256(packPercent[_packageID])) / baseDivider);
            
        order.start = block.timestamp;
        order.count += 1;

        UserInfo storage user_ref = userInfo[user.referrer];
        user_ref.refReward += (10 / (5 + order.count)) * (packagePrice[_packageID]* user_ref.maxPackPercent / baseDivider);

        if(user.maxPackPercent < uint256(packPercent[_packageID]))
            user.maxPackPercent = uint256(packPercent[_packageID]);
        
        user.up_profit += (10 / (5 + order.count)) * (packagePrice[_packageID]* user_ref.maxPackPercent / baseDivider);
        user.totalDeposit += packagePrice[_packageID];
        user.depositCount += 1;
        user.lastDeposit = block.timestamp;

        totalDepositCount += 1;
        totalDeposit += packagePrice[_packageID];

        emit Deposit(msg.sender, packagePrice[_packageID]);
    }

    function withdraw() external {
        UserInfo storage user = userInfo[msg.sender];
        uint256 cbalance = usdt.balanceOf(address(this));
        uint256 total_wd = user.withdrawable + user.refReward;

        if(cbalance <= total_wd){
            total_wd = cbalance;
            if(user.withdrawable <= cbalance){
                totalWithdraw += user.withdrawable;
                user.recWithdrawable -= user.withdrawable;
                cbalance -= user.withdrawable;
                user.withdrawable = 0;
                
                user.refReward -= cbalance;
                user.recRefReward += cbalance;
                totalReferWithdraw += cbalance;
            }else{
                user.withdrawable -= cbalance;
                user.recWithdrawable += cbalance;
                totalWithdraw += cbalance;
            }
        }else{
            user.recWithdrawable += user.withdrawable;
            totalWithdraw += user.withdrawable;
            user.withdrawable = 0;

            user.recRefReward += user.refReward;
            totalReferWithdraw += user.refReward;
            user.refReward = 0;
        }   

        usdt.transfer(msg.sender, total_wd);
        emit Withdraw(msg.sender, total_wd);    
    }

    function withdrawRef() external {
        uint256 cbalance = usdt.balanceOf(address(this));
        UserInfo storage user = userInfo[msg.sender];

        uint256 wdAmount = user.refReward;
        
        if(cbalance <= user.refReward){
            wdAmount = cbalance;
        }

        user.refReward -= wdAmount;
        user.recRefReward += wdAmount;
        totalReferWithdraw += wdAmount;
        usdt.transfer(msg.sender, wdAmount);
        emit WithdrawRef(msg.sender, wdAmount);
    }
    
}

