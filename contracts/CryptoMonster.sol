//SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract Token is ERC20("CryptoMonster", "CMON"){
    uint256 public startTime; // время старта системы
    uint256 Time_dif; // добавленное время
    uint256 privPhase = 10 minutes; // длительность приватной фазы
    uint256 seedPhase = 5 minutes; // длительной подготовительной фазы

    uint256 privPrice = 0.00075 ether; // цена токена в приватную фазу
    uint256 pubPrice = 0.001 ether; // цена токена в фазу открытой покупки
    uint256 dec = 10**decimals(); // кол-во десятичных знаков
    uint256 privAmount; // кол-во токенов определенное на приватную фазу покупки
    uint256 pubAmount; // кол-во токенов для фазы открытой покупки
    uint256 public counterToProvider = 0; // счетчик для автоматического перевода провайдерам их токены
    uint256 private availableOwnerTokens = 0; // кол-во размороженных токенов для владельца

    /*
        Адреса заранее зарегистрированных пользователей в системе
    */

    address owner;
    address privProv = 0xbD0233D4cb7abE917F79f0E80DC7676F4cb818e1;
    address pubProv = 0x7CE4B5D0504EdF27ec43610F8679E84BDF81a0b8;
    address inv1 = 0xCf6526a5165A8f406c9652a3b1e10669A60F5905;
    address inv2 = 0x6e36B3891d2ae499Ad3763767deA0119C363F015;
    address bf = 0x56c4c71e7C04e2f0D482BCc187392D4D96595694;

    /*
        Ролевая система
    */

    enum Role { User, publicProvider, privateProvider, Owner}

    /*
        Структура пользователя
    */

    struct User {
        string login;
        address wallet;
        uint256 seedTokens;
        uint256 privateTokens;
        uint256 publicTokens;
        bool whitelist;
        Role role;
    }

    /*
        Структура запроса в вайтлист
    */

    struct Whitelist {
        string login;
        address wallet;
        bool status;
    }

    /*
        Структура заявки на распоряжение своими токенами
    */

    struct Approve {
        address owner;
        address spender;
        uint256 amount;
        uint256 tokenType;
    }

    /*
        Маппинги для хранения данных пользователя
    */

    mapping (string => address) loginMap;
    mapping (address => User) userMap;
    mapping (string => bytes32) passwordMap;

    /*
        Массивы вайтлиста, запросов в вайтлист, список заявок на распоряжение своими токенами
    */

    Whitelist[] private requests;
    Whitelist[] private whitelist;
    Approve[] private approveList;

    constructor(){

        /*
            Объявление владельца системы, старта работы системы
            Минт владельцу 10 млн. токенов, распределения их по фазам, перевод инвесторам
        */

        owner = msg.sender;
        startTime = block.timestamp;
        _mint(owner, 10_000_000 * dec);
        privAmount = balanceOf(owner) * 30 / 100;
        pubAmount = balanceOf(owner) * 60 / 100;
        _transfer(owner, inv1, 300_000 * dec);
        _transfer(owner, inv2, 400_000 * dec);
        _transfer(owner, bf, 200_000 * dec);

        /*
            Регистрация в системе заранее внесенных юзеров
        */

        userMap[owner] = User("owner", owner, 100_000 * dec, privAmount, pubAmount, false, Role.Owner);
        loginMap["owner"] = owner;
        passwordMap["owner"] = keccak256(abi.encode("123"));

        userMap[pubProv] = User("pubProv", pubProv, 0, 0, 0, false, Role.publicProvider);
        loginMap["pubProv"] = pubProv;
        passwordMap["pubProv"] = keccak256(abi.encode("123"));

        userMap[privProv] = User("privProv", privProv, 0, 0, 0, true, Role.privateProvider);
        loginMap["privProv"] = privProv;
        passwordMap["privProv"] = keccak256(abi.encode("123"));

        userMap[inv1] = User("inv1", inv1, balanceOf(inv1), 0, 0, false, Role.User);
        loginMap["inv1"] = inv1;
        passwordMap["inv1"] = keccak256(abi.encode("123"));

        userMap[inv2] = User("inv2", inv2, balanceOf(inv2), 0, 0, false, Role.User);
        loginMap["inv2"] = inv2;
        passwordMap["inv2"] = keccak256(abi.encode("123"));

        userMap[bf] = User("bf", bf, balanceOf(bf), 0, 0, false, Role.User);
        loginMap["bf"] = bf;
        passwordMap["bf"] = keccak256(abi.encode("123"));
    }

    /*
        Модификатор доступа для ролевой системы
    */

    modifier AccessControl (Role _role){
        require(userMap[msg.sender].role == _role, unicode"У вас нет доступа");
        _;
    }

    /*
        Метод регистрации пользователя по логину и паролю
    */

    function signUp (string memory _login, string memory _password) public {
        require(loginMap[_login] == address(0), unicode"Пользователь с таким логином уже существует");
        require(userMap[msg.sender].wallet == address(0), unicode"Пользователь с таким адресом уже существует");
        userMap[msg.sender] = User(_login, msg.sender, 0, 0, 0, false, Role.User);
        loginMap[_login] = msg.sender;
        passwordMap[_login] = keccak256(abi.encode(_password));
    }

    /*
        Метод авторизации пользователя,  в случае успеха возвращает структуру пользователя
    */

    function signIn (string memory _login, string memory _password) public view returns (User memory) {
        require(passwordMap[_login] == keccak256(abi.encode(_password)), unicode"Неверно введены данные");
        return userMap[loginMap[_login]];
    }

    /*
        Метод добавляющий минуту к жизни системы
    */

    function addMinute() public {
        Time_dif += 1 minutes;
    }

    /*
        Метод возвращающий цену токена в зависимости от времени системы
    */

    function getTokenPrice() public view returns(uint256){
        uint256 tokenPrice = 0;
        if(getLifeTime() > seedPhase + privPhase){
            tokenPrice = pubPrice;
        }else if(getLifeTime() > seedPhase){
            tokenPrice = privPrice;
        }
        return tokenPrice;
    }

    /*
        Метод позволяющий отправить заявку в вайтлист, в случае если сейчас подготовительная фаза и заявка не была отправлена ранее
    */

    function sendRequestToWhitelist() public {
        require(getLifeTime() < seedPhase, unicode"Заявку можно подать только во время подготовительной фазы");
        require(!userMap[msg.sender].whitelist, unicode"Вы уже в вайтлисте");
        for(uint256 i = 0; i < requests.length; i++){
            require(requests[i].wallet != msg.sender, unicode"Вы уже подали заявку в вайтлист");
        }
        requests.push(Whitelist(userMap[msg.sender].login, msg.sender, false));
    }

    /*
        Метод для обработки заявок в вайтлисте
    */

    function takeWhitelistRequest(uint256 _index, bool _solution) public AccessControl(Role.privateProvider) {
        if(_solution){
            requests[_index].status = true;
            whitelist.push(Whitelist(requests[_index].login, requests[_index].wallet, true));
            userMap[requests[_index].wallet].whitelist = true;
        }else{
            delete requests[_index];
        }
    }

    /*
        Метод покупки токена
    */

    function buyToken(uint256 _amount) public payable {
        uint256 tokenPrice = getTokenPrice();
        if(tokenPrice == pubPrice){
            require(_amount / dec <= 5_000, unicode"Максимальное кол-во - 5.000 CMON");
            require(msg.value >= (_amount / dec) * tokenPrice, unicode"Недостаточно ETH");
            payable(owner).transfer(msg.value);
            _transfer(pubProv, msg.sender, _amount);
            userMap[msg.sender].publicTokens += _amount;
            userMap[pubProv].publicTokens -= _amount;
        }else if(tokenPrice == privPrice){
            require(userMap[msg.sender].whitelist, unicode"Free sale not started");
            require(_amount / dec <= 100_000, unicode"Максимальное кол-во - 100.000 CMON");
            require(msg.value >= (_amount / dec) * tokenPrice, unicode"Недостаточно ETH");
            payable(owner).transfer(msg.value);
            _transfer(privProv, msg.sender, _amount);
            userMap[msg.sender].privateTokens += _amount;
            userMap[privProv].privateTokens -= _amount;
        }else{
            revert(unicode"Во время подготовительной фазы нельзя покупать CMON");
        }
    }

    function stopPublicPhase() public AccessControl(Role.Owner){
        _transfer(pubProv, msg.sender, userMap[pubProv].publicTokens);
        userMap[msg.sender].publicTokens += userMap[pubProv].publicTokens;
        availableOwnerTokens += userMap[pubProv].publicTokens;
        userMap[pubProv].publicTokens = 0;
    }

    /*
        Метод для внутреннего перевода токенов провайдерам
    */

    function transferToProvider(uint256 _phase) public AccessControl(Role.Owner){
        if(_phase == 2){
            _transfer(msg.sender, privProv, privAmount);
            userMap[msg.sender].privateTokens -= privAmount;
            userMap[privProv].privateTokens += privAmount;
            counterToProvider = 1;
            availableOwnerTokens += 100_000 * dec;
        }else if(_phase == 3){
            _transfer(msg.sender, pubProv, pubAmount);
            userMap[msg.sender].publicTokens -= pubAmount;
            userMap[pubProv].publicTokens += pubAmount;
            counterToProvider = 2;
            _transfer(privProv, msg.sender, userMap[privProv].privateTokens);
            userMap[msg.sender].privateTokens += userMap[privProv].privateTokens;
            availableOwnerTokens += userMap[privProv].privateTokens;
            userMap[privProv].privateTokens = 0;
        }
    }

    /*
        Метод для перевода токенов между пользователями
    */

    function transferToken(address _receiver, uint256 _amount, uint256 _type) public {
        if (msg.sender == owner){
            require(availableOwnerTokens >= _amount, unicode"Вы не можете использовать токены для дальнейшей продажи");
        }
        if(_type == 1){
            require(userMap[msg.sender].seedTokens >= _amount, unicode"Недостаточно seed CMON");
            _transfer(msg.sender, _receiver, _amount);
            userMap[msg.sender].seedTokens -= _amount;
            userMap[_receiver].seedTokens += _amount;
        }else if(_type == 2){
            require(userMap[msg.sender].privateTokens >= _amount, unicode"Недостаточно private CMON");
            _transfer(msg.sender, _receiver, _amount);
            userMap[msg.sender].privateTokens -= _amount;
            userMap[_receiver].privateTokens += _amount;
        }else if(_type == 3){
            require(userMap[msg.sender].publicTokens >= _amount, unicode"Недостаточно public CMON");
            _transfer(msg.sender, _receiver, _amount);
            userMap[msg.sender].publicTokens -= _amount;
            userMap[_receiver].publicTokens += _amount;
        }
        if(_receiver == owner){
            availableOwnerTokens += _amount;
        }

    }

    /*
        Метод позволяющий дать в распоряжение свои public CMON токены
    */

    function approveToken(address spender, uint256 amount, uint256 _type) public {
        if(_type == 1){
            require(userMap[msg.sender].seedTokens >= amount, unicode"У вас недостаточно seed CMON");
            approveList.push(Approve(msg.sender, spender, amount, _type));
        }else if(_type == 2){
            require(userMap[msg.sender].privateTokens >= amount, unicode"У вас недостаточно private CMON");
            approveList.push(Approve(msg.sender, spender, amount, _type));
        }else if(_type == 3){
            require(userMap[msg.sender].publicTokens >= amount, unicode"У вас недостаточно public CMON");
            approveList.push(Approve(msg.sender, spender, amount, _type));
        }
    }

    /*
        Метод позволяющий забрать данные в распоряжение токены
    */

    function takeMyAllowance(uint256 _index) public {
        require(approveList[_index].spender == msg.sender, unicode"Это не ваши токены");
        transferFrom(approveList[_index].owner, approveList[_index].spender, approveList[_index].amount);
        if(approveList[_index].tokenType == 1){
            userMap[approveList[_index].owner].seedTokens -= approveList[_index].amount;
            userMap[approveList[_index].spender].seedTokens += approveList[_index].amount;
        }else if(approveList[_index].tokenType == 2){
            userMap[approveList[_index].owner].privateTokens -= approveList[_index].amount;
            userMap[approveList[_index].spender].privateTokens += approveList[_index].amount;
        }else if(approveList[_index].tokenType == 3){
            userMap[approveList[_index].owner].publicTokens -= approveList[_index].amount;
            userMap[approveList[_index].spender].publicTokens += approveList[_index].amount;
        }
        delete approveList[_index];
    }

    /*
        Метод для смены цены токена во время открытой фазы  покупки
    */

    function changePublicPrice(uint256 _price) public AccessControl(Role.publicProvider){
        pubPrice = _price;
    }

    /*
        Метод для награждения пользователей public CMON'ами
    */

    function giveReward(address _receiver, uint256 _amount) public AccessControl(Role.publicProvider) {
        require(userMap[pubProv].publicTokens >= _amount, unicode"Недостаточно public CMON");
        transfer(_receiver, _amount);
        userMap[msg.sender].publicTokens -= _amount;
        userMap[_receiver].publicTokens += _amount;
    }

    /*
        Метод возвращающий текущее время жизни системы
    */

    function getLifeTime() public view returns(uint256){
        return block.timestamp + Time_dif - startTime;
    }

    /*
        Метод возвращающий текущее время жизни системы
    */

    function getUserData(address _wallet) public view AccessControl(Role.Owner) returns (User memory) {
        return userMap[_wallet];
    }

    /*
        Метод возвращающий public CMON пользователя
    */

    function getUserPublicTokens(address _wallet) public view AccessControl(Role.publicProvider) returns (uint256) {
        return userMap[_wallet].publicTokens;
    }

    /*
        Метод возвращающий private CMON пользователя
    */

    function getUserPrivateTokens(address _wallet) public view AccessControl(Role.privateProvider) returns (uint256) {
        return userMap[_wallet].privateTokens;
    }

    /*
        Метод возвращающий список людей в вайтлисте
    */

    function getWhitelist() public view AccessControl(Role.privateProvider) returns (Whitelist[] memory){
        return whitelist;
    }

    /*
        Метод возвращающий список распоряженных токенов другим пользователям
    */

    function getApproveList() public view returns (Approve[] memory){
        return approveList;
    }

    /*
        Метод возвращающий список заявок в вайтлист
    */

    function getWhitelistRequests() public view AccessControl(Role.privateProvider) returns (Whitelist[] memory){
        return requests;
    }

    /*
        Метод возвращающий баланс пользователя
    */

    function getBalance() public view returns (uint256, uint256, uint256, uint256){
        return (msg.sender.balance, userMap[msg.sender].seedTokens, userMap[msg.sender].privateTokens, userMap[msg.sender].publicTokens);
    }

    /*
        Метод возвращающий кол-во знаков после запятой
    */

    function decimals() public view virtual override returns (uint8) {
        return 12;
    }

}