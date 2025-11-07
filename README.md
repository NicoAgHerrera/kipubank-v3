# 🏦 KipuBank V3 - Banco DeFi Unificado en USDC con Uniswap V2

## 📘 Descripción General

**KipuBankV3** es la evolución natural del proyecto **KipuBankV2**, transformando un banco multi-token con oráculos en una **aplicación DeFi real**, totalmente integrada con **Uniswap V2**.

Su objetivo es **unificar todos los depósitos, ya sean ETH o tokens ERC-20, en un balance único denominado en USDC**, garantizando la liquidez, la transparencia y la consistencia contable.

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

## ⚙️ 2. Despliegue de KipuBank V3

## 🧩 Requisitos Previos

- **Foundry** (`forge`) instalado.
- **Clave privada** con **ETH de Sepolia**.
- **RPC de Sepolia** (Infura, Alchemy o similar).
- **API Key de Etherscan** (para verificación automática).
---

## 🧱 Proceso de Despliegue (Foundry + Script)

### 1) Clonar el repo
```bash
git clone https://github.com/<usuario>/kipubank-v3.git
cd kipubank-v3
```

### 2) Instalar dependencias
```bash
forge install openzeppelin/openzeppelin-contracts
forge install Uniswap/v2-core
forge install Uniswap/v2-periphery
```

### 3) Revisar el script de deploy  
Editar **`script/DeployKipuBankV3.s.sol`** y confirmar:

- **Direcciones en Sepolia** (ya seteadas en el script):
  - `factory` (Uniswap V2 Factory): `0xDAe3a9CbFe88dB2a9F7A189AfEA5a3B08347C07b`
  - `usdc`: `0xf08a50178dfcde18524640ea6618a1f965821715`
  - `weth`: `0x7b79995e5f793a07bc00c21412e50ecae098e7f9`
- **Límites (en USDC, 6 decimales)**:
  ```solidity
  uint256 bankCap     = 1_000_000 * 10**6; // 1M USDC
  uint256 withdrawCap =    10_000 * 10**6; // 10k USDC
  ```

> Nota: los límites están en **USDC** (6 decimales). Tener 0.09 ETH no afecta estos topes.

### 4) Compilar
```bash
forge build
```

### 5) Desplegar (vía script)
```bash
forge script script/DeployKipuBankV3.s.sol   --rpc-url https://sepolia.infura.io/v3/<API_KEY>   --private-key 0xTU_PRIVATE_KEY   --broadcast
```

> Al finalizar, Foundry muestra la **dirección del contrato**.  
> Ejemplo real del despliegue: `0x5dBe19153CC0b9C5750aE662109E7Cd59C266381` (Sepolia).

---

## 🔍 Verificación en Etherscan

### Opción A — Automática (recomendada)
Si ya tenés `ETHERSCAN_API_KEY` en tu entorno:
```bash
forge script script/DeployKipuBankV3.s.sol   --rpc-url $SEPOLIA_RPC_URL   --private-key $PRIVATE_KEY   --broadcast   --verify   --etherscan-api-key $ETHERSCAN_API_KEY -vvvv
```

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
