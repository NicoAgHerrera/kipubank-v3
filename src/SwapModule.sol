///SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/*///////////////////////////////////
            Imports
///////////////////////////////////*/
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IUniswapV2Factory} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

/*///////////////////////////////////
            Libraries
///////////////////////////////////*/
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract SwapModule {
    using SafeERC20 for IERC20;
    /*///////////////////////////////////
            Variables de estado
    ///////////////////////////////////*/
    /// @notice Factory de Uniswap V2 para obtener pares
    IUniswapV2Factory public immutable FACTORY;

    /*///////////////////////////////////
                Eventos
    ///////////////////////////////////*/
    event SwapModule_SwapExecuted(
        address indexed user,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    /*///////////////////////////////////
                Errores
    ///////////////////////////////////*/
    error SwapModule_InsufficientOutputAmount();
    error SwapModule_InsufficientLiquidity();
    error SwapModule_PairDoesNotExist();
    error SwapModule_InvalidAddress();
    error SwapModule_InvalidAmount();

    /*///////////////////////////////////
                Modificadores
    ///////////////////////////////////*/
    /// @notice Valida que ambas direcciones no sean cero y sean diferentes
    /// @param tokenA Primera dirección a validar
    /// @param tokenB Segunda dirección a validar
    modifier validTokenAddresses(address tokenA, address tokenB) {
        if (tokenA == address(0) || tokenB == address(0)) {
            revert SwapModule_InvalidAddress();
        }
        if (tokenA == tokenB) {
            revert SwapModule_InvalidAddress();
        }
        _;
    }

    /// @notice Valida que la cantidad sea mayor que cero
    /// @param amount Cantidad a validar
    modifier validAmount(uint256 amount) {
        if (amount == 0) {
            revert SwapModule_InvalidAmount();
        }
        _;
    }

    /// @notice Valida que el par de tokens exista en el factory
    /// @param tokenA Primer token
    /// @param tokenB Segundo token
    modifier pairExists(address tokenA, address tokenB) {
        address pair = FACTORY.getPair(tokenA, tokenB);
        if (pair == address(0)) {
            revert SwapModule_PairDoesNotExist();
        }
        _;
    }

    /*///////////////////////////////////
                constructor
    ///////////////////////////////////*/
    constructor(address _factory) {
        FACTORY = IUniswapV2Factory(_factory);
    }

    /*///////////////////////////////////
                Funciones principales
    ///////////////////////////////////*/

    /**
     * @notice Función para ejecutar swaps de inputs exactos en Uniswap V2
     * @notice Los outputs pueden variar según el valor mínimo amountOutMin
     * @param tokenIn La dirección del token de entrada
     * @param tokenOut La dirección del token de salida
     * @param amountIn La cantidad a intercambiar
     * @param amountOutMin La cantidad mínima aceptada después de un swap
     * @dev Esta función sigue las mejores prácticas de Uniswap V2
     * @return amountOut cantidad de tokens recibidos
     */
    function swapExactInputSingle(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin
    )
        external
        validTokenAddresses(tokenIn, tokenOut)
        validAmount(amountIn)
        pairExists(tokenIn, tokenOut)
        returns (uint256 amountOut)
    {
        // Obtener el par (ya validado por el modificador pairExists)
        address pair = FACTORY.getPair(tokenIn, tokenOut);

        // 1. Obtener reservas antes del swap (para cálculo)
        (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(pair)
            .getReserves();

        // Determinar cuál token es token0 y token1
        address token0 = IUniswapV2Pair(pair).token0();
        bool token0IsTokenIn = token0 == tokenIn;

        // 2. Calcular la cantidad de salida esperada
        uint256 amountOutExpected = getAmountOut(
            amountIn,
            token0IsTokenIn ? reserve0 : reserve1,
            token0IsTokenIn ? reserve1 : reserve0
        );

        // Verificar que el cálculo produce al menos el mínimo esperado
        if (amountOutExpected < amountOutMin) {
            revert SwapModule_InsufficientOutputAmount();
        }

        // 3. Transferir tokens del usuario al par usando SafeERC20
        IERC20(tokenIn).safeTransferFrom(msg.sender, pair, amountIn);

        // 4. Registrar balance antes del swap para verificación
        uint256 balanceBefore = IERC20(tokenOut).balanceOf(address(this));

        // 5. Realizar el swap en el par
        uint256 amount0Out;
        uint256 amount1Out;
        if (token0IsTokenIn) {
            amount0Out = 0;
            amount1Out = amountOutExpected;
        } else {
            amount0Out = amountOutExpected;
            amount1Out = 0;
        }

        IUniswapV2Pair(pair).swap(amount0Out, amount1Out, address(this), "");

        // 6. Obtener balance después del swap y calcular amountOut real
        uint256 balanceAfter = IERC20(tokenOut).balanceOf(address(this));
        amountOut = balanceAfter - balanceBefore;

        // 7. Verificar que recibimos al menos el mínimo esperado (seguridad extra)
        if (amountOut < amountOutMin) {
            revert SwapModule_InsufficientOutputAmount();
        }

        // 8. Transferir tokens de salida al usuario usando SafeERC20
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);

        emit SwapModule_SwapExecuted(
            msg.sender,
            tokenIn,
            tokenOut,
            amountIn,
            amountOut
        );

        return amountOut;
    }

    /**
     * @notice Función auxiliar para calcular la cantidad de salida
     * @param amountIn Cantidad de entrada
     * @param reserveIn Reserva del token de entrada
     * @param reserveOut Reserva del token de salida
     * @return amountOut Cantidad calculada de salida
     * @dev Implementa la fórmula AMM de Uniswap V2: amountOut = (amountIn * 997 * reserveOut) / (reserveIn * 1000 + amountIn * 997)
     */
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) public pure returns (uint256 amountOut) {
        if (amountIn == 0 || reserveIn == 0 || reserveOut == 0) {
            revert SwapModule_InsufficientLiquidity();
        }

        // Uniswap V2 tiene una fee del 0.3% (3/1000)
        // El input se multiplica por 997 (1000 - 3)
        uint256 amountInWithFee = amountIn * 997;

        // Calcular el denominador y numerador
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * 1000) + amountInWithFee;

        amountOut = numerator / denominator;
    }

    /**
     * @notice Función para obtener el par de tokens
     * @param tokenA Primer token
     * @param tokenB Segundo token
     * @return pair Dirección del par
     */
    function getPair(
        address tokenA,
        address tokenB
    ) external view returns (address pair) {
        return FACTORY.getPair(tokenA, tokenB);
    }
}