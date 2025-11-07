# 🏦 KipuBank V3 — Banco DeFi Unificado en USDC con Uniswap V2

## 📘 Descripción General

**KipuBankV3** es la evolución natural del proyecto **KipuBankV2**, transformando un banco multi-token con oráculos en una **aplicación DeFi real**, totalmente integrada con **Uniswap V2**.

Su objetivo es **unificar todos los depósitos —ya sean ETH o tokens ERC-20— en un balance único denominado en USDC**, garantizando la liquidez, la transparencia y la consistencia contable.

Este nuevo diseño elimina por completo los oráculos de precios y utiliza el mercado real de Uniswap como fuente de valor, consolidando el aprendizaje del módulo de **composabilidad y protocolos DeFi**.

---

## 🚀 1. Mejoras Implementadas y Motivación

### 🔹 1.1 Integración directa con Uniswap V2
- **Antes (V2):** el contrato dependía de oráculos Chainlink para calcular el valor en USD de los tokens.  
- **Ahora (V3):** los tokens se intercambian *on-chain* mediante Uniswap V2 Router, obteniendo su precio real de mercado.  
- **Motivo:** eliminar la dependencia de oráculos externos y adoptar un enfoque verdaderamente descentralizado basado en liquidez.

---

### 🔹 1.2 Depósitos generalizados y conversión automática
El contrato acepta:

- **ETH nativo**, convertido automáticamente a WETH y luego a USDC.  
- **USDC directo**, que se acredita sin swap.  
- **Cualquier token ERC-20** que posea un par directo con USDC en Uniswap.  

**Motivo:** simplificar la experiencia del usuario y permitir depósitos de cualquier activo sin requerir configuración previa ni feeds manuales.

---

### 🔹 1.3 Eliminación total de oráculos Chainlink
- Se reemplaza la lógica de feeds por **swaps reales** en Uniswap.  
- Las conversiones a USDC son verificables en cadena y reflejan el precio real del mercado.  
- **Motivo:** mejorar la transparencia y reducir complejidad administrativa (sin registrar ni mantener feeds).

---

### 🔹 1.4 Arquitectura modular
- Se introduce el contrato auxiliar **SwapModule**, responsable exclusivo de interactuar con Uniswap (factory, router y pares).  
- El contrato principal (**KipuBankV3**) mantiene solo la lógica bancaria y de contabilidad.  
- **Motivo:** separación de responsabilidades, mayor legibilidad y facilidad de testing.

---

### 🔹 1.5 Seguridad mejorada
- Uso de **ReentrancyGuard** y **SafeERC20** (OpenZeppelin).  
- Validaciones estrictas con modificadores `nonZero`.  
- Límites operativos (`bankCapUSDC`, `withdrawalCapUSDC`) definidos como inmutables.  
- **Motivo:** prevenir vulnerabilidades comunes, proteger la liquidez y mantener eficiencia de gas.

---

### 🔹 1.6 Contabilidad unificada en USDC
- Todos los depósitos se registran en una **única bóveda por usuario** (`mapping(address → Vault)`).  
- El saldo interno se expresa en USDC con 6 decimales.  
- **Motivo:** simplificar la lógica y facilitar auditorías al eliminar la multiplicidad de tokens y feeds.

---

## ⚙️ 2. Despliegue

### 🧩 Requisitos Previos

- **Remix IDE** o **Foundry (`forge`)**  
- **MetaMask** configurado en **Sepolia** u otra testnet compatible  
- **Fondos de testnet ETH** para gas  
- **Dirección de la UniswapV2Factory** y tokens **USDC / WETH** en la red elegida  

---
# ⚙️ Despliegue de KipuBankV3

## 🧩 Requisitos Previos

- **Foundry** (`forge`) correctamente instalado y configurado.  
- **MetaMask** o **clave privada** con fondos de **ETH de testnet**.  
- **Red Sepolia** (u otra testnet compatible) conectada al **RPC correspondiente**.  
- **Direcciones válidas** de:
  - UniswapV2Factory  
  - USDC  
  - WETH9  

---

## 🧱 Proceso de Despliegue (Foundry)

### 1. Clonar el repositorio

```bash
git clone https://github.com/<usuario>/kipubank-v3.git
cd kipubank-v3
```

---

### 2. Instalar dependencias necesarias

```bash
forge install openzeppelin/openzeppelin-contracts
forge install Uniswap/v2-core
forge install Uniswap/v2-periphery
```

---

### 3. Compilar el proyecto

```nginx
forge build
```

---

### 4. Desplegar el contrato

Reemplazá los valores entre `< >` con los reales.

```php-template
forge create src/KipuBankV3.sol:KipuBankV3   --rpc-url <RPC_URL>   --private-key <PRIVATE_KEY>   --constructor-args <FACTORY_ADDRESS> <USDC_ADDRESS> <WETH_ADDRESS> <BANK_CAP_USDC> <WITHDRAW_CAP_USDC>
```

#### Ejemplo:

```lua
forge create src/KipuBankV3.sol:KipuBankV3   --rpc-url https://sepolia.infura.io/v3/<API_KEY>   --private-key 0xABCDEF...   --constructor-args 0xUniswapFactory 0xUSDC 0xWETH 1000000000000 1000000000000
```

---

### 5. Guardar la dirección del contrato desplegado

Anotá o copiá la **dirección del contrato** que devuelve el comando anterior para futuras verificaciones y pruebas.

---

### 🔍 Verificación en Etherscan / Blockscout

1. Copiar la dirección del contrato desplegado.  
2. Ir a la pestaña **Verify & Publish Contract** del explorador.  
3. Configurar:
- **Compilador:** Solidity 0.8.30  
- **Optimization:** Yes  
- **License:** MIT  
4. Pegar el código fuente y verificar.  
5. El explorador mostrará todas las funciones públicas para interacción directa.

---

## 🧭 3. Interacción

### 💰 Depósitos

| Activo | Método | Descripción |
|---------|--------|-------------|
| **ETH nativo** | `depositETH(uint256 amountOutMin)` | Convierte ETH a WETH y luego a USDC vía Uniswap. |
| **Token ERC-20 (no USDC)** | `depositToken(address token, uint256 amount, uint256 amountOutMin)` | Convierte cualquier token soportado a USDC. |
| **USDC** | `depositToken(address USDC, uint256 amount, 0)` | Acredita directamente el monto en la bóveda. |

> ⚠️ Antes de llamar a `depositToken`, el usuario debe ejecutar `approve()` sobre el token que desea depositar.

---

### 💸 Retiros

| Operación | Método | Descripción |
|------------|--------|-------------|
| **Retirar USDC** | `withdrawUSDC(uint256 amount)` | Envía USDC directamente al usuario respetando el límite máximo por retiro. |

---

### 🔎 Consultas

| Función | Descripción |
|----------|-------------|
| `getVault(address user)` | Devuelve saldo, depósitos y retiros del usuario (en USDC). |
| `getTotalUSDC()` | Devuelve el total global custodiado por el banco. |

---

## 🧩 4. Notas de Diseño y Trade-Offs

### 🔸 Descentralización Real
Se elimina cualquier dependencia de oráculos centralizados (Chainlink).  
El sistema se apoya enteramente en Uniswap, asegurando precios determinados por el mercado y liquidez real.

---

### 🔸 Simplificación del Modelo Contable
Cada usuario posee una **única bóveda unificada** expresada en USDC.  
Esto elimina la necesidad de mappings anidados y reduce el consumo de gas y almacenamiento.

---

### 🔸 Trade-Off: Dependencia del Liquidity Pool
Los precios dependen del estado de los pools de Uniswap.  
Si el par (token, USDC) tiene poca liquidez, pueden producirse desviaciones o *slippage*.  
Se mitiga con el parámetro `amountOutMin` en cada operación.

---

### 🔸 Trade-Off: Menor previsibilidad frente a feeds fijos
A diferencia de Chainlink, los swaps reflejan precios dinámicos en tiempo real.  
Esto mejora la descentralización, pero introduce variabilidad según el bloque y la liquidez.

---

### 🔸 Seguridad sobre optimización de gas
Se priorizó el uso de **SafeERC20**, **ReentrancyGuard** y el patrón *checks-effects-interactions* por encima de la micro-optimización.  
El diseño privilegia la robustez y la claridad por sobre unos pocos ahorros de gas.

---

### 🔸 Capacidad del Banco (Bank Cap)
Todo depósito se valida comparando el total proyectado (`s_totalUSDC + monto`) contra el límite `i_bankCapUSDC`.  
Si el nuevo total excede el cap, la transacción revierte automáticamente (`BankCapExceeded`).  
Garantiza estabilidad operativa y evita concentraciones excesivas de liquidez.

---

### 🔸 Modularidad Extensible
**SwapModule** puede reutilizarse en otros contratos DeFi para ejecutar swaps seguros sin duplicar lógica.  
Permite que futuros módulos (por ejemplo, préstamos o staking) se integren fácilmente.

---

## ✅ 5. Conclusión

**KipuBankV3** representa una versión completamente funcional y escalable del concepto de banco descentralizado.  
Integra protocolos reales, respeta estándares de seguridad y unifica la experiencia de usuario bajo un sistema transparente, auditable y basado en mercado.
