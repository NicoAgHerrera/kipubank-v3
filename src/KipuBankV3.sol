// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/*//////////////////////////////////////////////////////////////
                        DEPENDENCIAS
//////////////////////////////////////////////////////////////*/
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SwapModule} from "./SwapModule.sol";

/**
 * @notice Interfaz mínima del estándar IWETH9.
 * @dev Permite envolver ETH nativo en WETH (ERC-20 equivalente)
 *      para operar dentro de Uniswap V2, que no admite ETH directamente.
 */
interface IWETH {
    function deposit() external payable;
    function withdraw(uint256) external;
}

/*//////////////////////////////////////////////////////////////////////////
                        CONTRATO PRINCIPAL: KipuBankV3
//////////////////////////////////////////////////////////////////////////*/

/*
 * @title KipuBankV3
 * @notice Contrato inteligente que implementa un banco DeFi sobre Ethereum,
 *         integrando directamente el protocolo Uniswap V2 a través del módulo
 *         `SwapModule`, con el objetivo de unificar todos los depósitos, sin
 *         importar el activo original, en un balance único denominado en USDC.
 *
 * @dev
 * ▪ Esta versión (V3) reemplaza completamente el sistema de valuación de la V2,
 *   eliminando la dependencia de oráculos de precios (Chainlink) y aplicando una
 *   conversión real on-chain mediante operaciones de swap directas.
 *
 * ▪ Características principales:
 *    - Integración DeFi directa: todos los tokens depositados (incluido ETH)
 *      se convierten automáticamente a USDC utilizando Uniswap V2.
 *    - Contabilidad unificada: el banco mantiene un único tipo de saldo
 *      interno expresado en USDC (6 decimales), simplificando la gestión y los
 *      controles de capacidad (`i_bankCapUSDC` y `i_withdrawalCapUSDC`).
 *    - Seguridad mejorada:
 *         • Implementa `ReentrancyGuard` (OpenZeppelin).
 *         • Emplea `SafeERC20` para transferencias seguras.
 *    - Arquitectura modular: delega la interacción con Uniswap V2 al contrato externo `SwapModule`.
 *    - Compatibilidad con tokens ERC-20 estándar y ETH nativo:
 *      acepta cualquier activo con par directo a USDC en Uniswap.
 *    - Eliminación de oráculos: ya no se requiere registrar feeds ni
 *      administrar decimales manualmente; el precio es determinado por el
 *      mercado en tiempo real.
 *
 * ▪ Principios de diseño:
 *    - Uso del patrón checks-effects-interactions en todas las funciones.
 *    - Variables `immutable` para mejorar eficiencia y seguridad.
 *    - Comentarios técnicos alineados con estándares profesionales DeFi.
 *
 * @version 3.0
 */
contract KipuBankV3 is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                               ROLES
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Rol administrativo que permite funciones de gestión.
     * @dev Deriva de `AccessControl` (OpenZeppelin).
     *      Por defecto, el `msg.sender` obtiene los roles `DEFAULT_ADMIN_ROLE`
     *      y `ADMIN_ROLE` al momento del despliegue.
     */
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /*//////////////////////////////////////////////////////////////
                           DEPENDENCIAS EXTERNAS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Instancia del módulo SwapModule utilizado para interactuar con Uniswap V2.
     * @dev El módulo se despliega en el constructor a partir de la dirección de la Factory.
     */
    SwapModule public immutable swapper;

    /**
     * @notice Direcciones de los tokens base utilizados por el sistema.
     * @dev `USDC` es el token contable interno y `WETH` se usa para envolver ETH nativo.
     */
    address public immutable USDC;
    address public immutable WETH;

    /**
     * @notice Decimales estándar de USDC (6).
     */
    uint8 public constant USDC_DECIMALS = 6;

    /*//////////////////////////////////////////////////////////////
                            ESTRUCTURAS DE DATOS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Representa la bóveda individual de cada usuario.
     * @dev
     * - A diferencia del V2, ahora cada usuario posee una sola bóveda
     *   expresada únicamente en USDC.
     * - Se almacenan los totales de depósitos y retiros de un usuario a modo estadístico.
     */
    struct Vault {
        uint256 amountUSDC;    // saldo actual del usuario expresado en USDC
        uint32 deposits;       // cantidad de operaciones de depósito realizadas
        uint32 withdrawals;    // cantidad de operaciones de retiro realizadas
    }

    /*//////////////////////////////////////////////////////////////
                          VARIABLES DE ESTADO
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Tope global de fondos que el banco puede custodiar (en USDC).
     * @dev Evita que la suma total (`s_totalUSDC`) exceda el límite operativo.
     */
    uint256 public immutable i_bankCapUSDC;

    /**
     * @notice Tope máximo de retiro permitido por transacción (en USDC).
     */
    uint256 public immutable i_withdrawalCapUSDC;

    /**
     * @notice Contador global de fondos almacenados (en USDC).
     * @dev Se actualiza automáticamente en cada depósito o retiro.
     */
    uint256 private s_totalUSDC;

    /**
     * @notice Mapeo principal que asocia cada usuario con su bóveda USDC.
     */
    mapping(address => Vault) private s_vaults;

    /*//////////////////////////////////////////////////////////////
                                 EVENTOS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Se emite cuando un usuario realiza un depósito exitoso.
     * @param user Dirección del usuario que deposita.
     * @param amountUSDC Monto acreditado en la bóveda (ya convertido a USDC).
     * @param newBalance Saldo actualizado del usuario tras el depósito.
     * @dev Permite auditar todos los ingresos de fondos expresados en valor final USDC.
     */
    event Deposited(address indexed user, uint256 amountUSDC, uint256 newBalance);

    /**
     * @notice Se emite cuando un usuario retira fondos de su bóveda.
     * @param user Dirección del usuario que retira.
     * @param amountUSDC Monto retirado (en USDC).
     * @param newBalance Saldo restante en la bóveda del usuario.
     * @dev Facilita el seguimiento de operaciones de salida.
     */
    event Withdrawn(address indexed user, uint256 amountUSDC, uint256 newBalance);

    /*//////////////////////////////////////////////////////////////
                                 ERRORES
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Lanza cuando se intenta operar con un monto nulo.
     * @dev Previene ejecuciones vacías que consumirían gas innecesariamente.
     */
    error ZeroAmount();

    /**
     * @notice Lanza si la suma total de fondos supera el límite global permitido.
     * @param attempted Valor total resultante tras el intento de depósito.
     * @param cap Límite global (`i_bankCapUSDC`) definido al desplegar.
     */
    error BankCapExceeded(uint256 attempted, uint256 cap);

    /**
     * @notice Lanza si un usuario intenta retirar más de su saldo disponible.
     * @param available Saldo disponible en su bóveda.
     * @param requested Monto solicitado.
     */
    error InsufficientBalance(uint256 available, uint256 requested);

    /**
     * @notice Lanza si el retiro supera el límite máximo por transacción.
     * @param requested Monto solicitado (en USDC).
     * @param max Límite de retiro por transacción.
     */
    error WithdrawalCapExceeded(uint256 requested, uint256 max);

    /*//////////////////////////////////////////////////////////////
                                MODIFICADORES
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Verifica que el monto ingresado sea distinto de cero.
     */
    modifier nonZero(uint256 amt) {
        if (amt == 0) revert ZeroAmount();
        _;
    }

    /*//////////////////////////////////////////////////////////////
                                CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    /*
     * @notice Inicializa el contrato configurando límites operativos y dependencias externas.
     *
     * @param _factory Dirección del contrato UniswapV2Factory.
     * @param _usdc    Dirección del token USDC (activo contable principal).
     * @param _weth    Dirección del contrato WETH9.
     * @param _bankCapUSDC       Tope global del banco (en USDC).
     * @param _withdrawalCapUSDC Tope máximo de retiro por transacción (en USDC).
     *
     * @dev
     * - Despliega una nueva instancia del módulo `SwapModule`, encargada de las
     *   interacciones con los pares de liquidez de Uniswap.
     * - Otorga los roles administrativos al `msg.sender`.
     * - Usa variables `immutable` para optimizar gas y evitar modificaciones futuras.
     */
    constructor(
        address _factory,
        address _usdc,
        address _weth,
        uint256 _bankCapUSDC,
        uint256 _withdrawalCapUSDC
    ) {
        swapper = new SwapModule(_factory);
        USDC = _usdc;
        WETH = _weth;
        i_bankCapUSDC = _bankCapUSDC;
        i_withdrawalCapUSDC = _withdrawalCapUSDC;

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    /*//////////////////////////////////////////////////////////////
                               DEPÓSITOS
    //////////////////////////////////////////////////////////////*/

    /**
    * @notice Función especial que se ejecuta automáticamente cuando el contrato recibe ETH sin datos (`data` vacío).
    * @dev En esta versión (V3), se revierte cualquier envío directo de ETH para evitar que se saltee
    *      la conversión obligatoria a USDC y el control de slippage. Los depósitos deben realizarse
    *      únicamente mediante la función `depositETH(uint256 amountOutMin)`.
    */
    receive() external payable {
        revert("Use depositETH");
    }

    /*
     * @notice Permite depositar ETH nativo, que será automáticamente convertido a USDC.
     *
     * @param amountOutMin Cantidad mínima de USDC esperada (protección contra slippage).
     *
     * @dev
     * ▪ Funcionamiento interno:
     *    1. Se recibe ETH nativo mediante `msg.value`.
     *    2. Se envuelve a WETH usando `IWETH.deposit{value: msg.value}()`.
     *    3. Se autoriza al módulo `SwapModule` a usar esos WETH.
     *    4. Se ejecuta el swap WETH → USDC con Uniswap V2.
     *    5. Se acredita el resultado (USDC) en la bóveda del usuario.
     *
     * ▪ Seguridad:
     *    - Protegida por `nonReentrant`.
     *    - Controla montos nulos con `nonZero`.
     *    - Previene slippage excesivo mediante el parámetro `_amountOutMin`.
     *
     * @example
     *   kipuBank.depositETH{value: 1 ether}(990_000); // acepta al menos 990 USDC
     */
    function depositETH(uint256 amountOutMin)
        external
        payable
        nonReentrant
        nonZero(msg.value)
    {
        IWETH(WETH).deposit{value: msg.value}();
        IERC20(WETH).safeIncreaseAllowance(address(swapper), msg.value);

        uint256 usdcReceived = swapper.swapExactInputSingle(
            WETH,
            USDC,
            msg.value,
            amountOutMin
        );

        _credit(msg.sender, usdcReceived);
    }

    /*
     * @notice Permite depositar cualquier token ERC-20 admitido.
     *
     * @param token Dirección del token a depositar.
     * @param amount Monto del token.
     * @param amountOutMin Mínimo de USDC aceptado (protección de slippage).
     *
     * @dev
     * ▪ Si el token es USDC, el depósito se acredita directamente sin swap.
     * ▪ Si es otro token ERC-20, se ejecuta un swap hacia USDC mediante el módulo.
     * ▪ En todos los casos, el resultado final se acredita en USDC.
     *
     * ▪ Seguridad:
     *    - Requiere `approve()` previo del token.
     *    - Protegido por `ReentrancyGuard` y `SafeERC20`.
     *
     * @example
     *   // Depositar 100 DAI (conversión automática a USDC)
     *   kipuBank.depositToken(address(DAI), 100e18, 99e6);
     */
    function depositToken(
        address token,
        uint256 amount,
        uint256 amountOutMin
    ) external nonReentrant nonZero(amount) {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        uint256 usdcReceived;
        if (token == USDC) {
            usdcReceived = amount;
        } else {
            IERC20(token).safeIncreaseAllowance(address(swapper), amount);
            usdcReceived = swapper.swapExactInputSingle(
                token,
                USDC,
                amount,
                amountOutMin
            );
        }

        _credit(msg.sender, usdcReceived);
    }

    /*//////////////////////////////////////////////////////////////
                             REGISTRO DE DEPÓSITOS
    //////////////////////////////////////////////////////////////*/
    /*
     * @notice Registra un depósito exitoso en la bóveda del usuario.
     *
     * @param user Dirección del usuario.
     * @param amountUSDC Monto equivalente en USDC recibido tras el swap.
     *
     * @dev
     * ▪ Actualiza la contabilidad global (`s_totalUSDC`) y la individual.
     * ▪ Rechaza la operación si el nuevo total excede `i_bankCapUSDC`.
     * ▪ Emite el evento `Deposited` al finalizar.
     *
     * @security
     * Sigue el patrón *checks-effects-interactions* y no interactúa con contratos externos.
     */
    function _credit(address user, uint256 amountUSDC) internal {
        uint256 newTotal = s_totalUSDC + amountUSDC;
        if (newTotal > i_bankCapUSDC) revert BankCapExceeded(newTotal, i_bankCapUSDC);

        s_totalUSDC = newTotal;
        Vault storage v = s_vaults[user];
        v.amountUSDC += amountUSDC;
        v.deposits += 1;

        emit Deposited(user, amountUSDC, v.amountUSDC);
    }

    /*//////////////////////////////////////////////////////////////
                                 RETIROS
    //////////////////////////////////////////////////////////////*/
    /*
     * @notice Permite al usuario retirar sus fondos en USDC.
     *
     * @param amountUSDC Monto de USDC a retirar.
     *
     * @dev
     * ▪ Valida:
     *    - Monto > 0.
     *    - Suficiencia de saldo.
     *    - Cumplimiento del límite por transacción (`i_withdrawalCapUSDC`).
     * ▪ Actualiza la bóveda y transfiere el USDC al usuario.
     * ▪ Emite el evento `Withdrawn`.
     *
     * @security
     * - Protegido con `nonReentrant`.
     * - Usa `SafeERC20.safeTransfer` para evitar errores de transferencia.
     *
     * @example
     *   kipuBank.withdrawUSDC(100); // Retira 100 USDC
     */
    function withdrawUSDC(uint256 amountUSDC)
        external
        nonReentrant
        nonZero(amountUSDC)
    {
        Vault storage v = s_vaults[msg.sender];
        if (v.amountUSDC < amountUSDC)
            revert InsufficientBalance(v.amountUSDC, amountUSDC);
        if (amountUSDC > i_withdrawalCapUSDC)
            revert WithdrawalCapExceeded(amountUSDC, i_withdrawalCapUSDC);

        v.amountUSDC -= amountUSDC;
        v.withdrawals += 1; 
        s_totalUSDC -= amountUSDC;

        IERC20(USDC).safeTransfer(msg.sender, amountUSDC);
        emit Withdrawn(msg.sender, amountUSDC, v.amountUSDC);
    }

    /*//////////////////////////////////////////////////////////////
                                   VISTAS
    //////////////////////////////////////////////////////////////*/
    /**
     * @notice Devuelve los datos de la bóveda individual de un usuario.
     * @param user Dirección del usuario.
     * @return amountUSDC Saldo actual expresado en USDC.
     * @return deposits Número total de depósitos.
     * @return withdrawals Número total de retiros.
     * @dev Función de solo lectura para auditorías o frontends.
     */
    function getVault(address user)
        external
        view
        returns (uint256 amountUSDC, uint32 deposits, uint32 withdrawals)
    {
        Vault storage v = s_vaults[user];
        return (v.amountUSDC, v.deposits, v.withdrawals);
    }

    /**
     * @notice Devuelve el total de fondos USDC administrados por el banco.
     * @return Total en USDC (`s_totalUSDC`).
     * @dev Permite monitorear la capacidad frente al límite global.
     */
    function getTotalUSDC() external view returns (uint256) {
        return s_totalUSDC;
    }
}
