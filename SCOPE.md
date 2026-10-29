# Proyecto final: CertificateRegistry

## Alcance
Smart contract que registra certificados de cursos y permite verificarlos on-chain.

**Incluye**
- Roles: `admin` (gestiona emisores) e `ISSUER_ROLE` (emite certificados).
- Emitir certificado: `(student, courseId, documentHash)`.
- Revocar certificado (admin o emisor original).
- Verificar: `getCertificate(id)` y `verify(id, documentHash)`.
- Despliegue local en Anvil con script de Foundry.

**Fuera de alcance**: testnet/mainnet, frontend, IPFS, NFTs/ERC-721, pagos, upgradeability.

## Decisiones de diseño (para defender en la evaluación)
| Decisión | Por qué | Alternativa descartada |
|---|---|---|
| Guardar solo `documentHash`, no el PDF ni datos personales | Costo de gas y privacidad (los datos on-chain son públicos para siempre) | Guardar URI/metadata en claro |
| `AccessControl` de OpenZeppelin con rol `ISSUER_ROLE` | Código auditado; permite varios emisores y rotarlos | `Ownable` (un único emisor) o roles propios |
| Admin **no** emite por defecto | Separación de funciones: quien gestiona permisos no emite | Admin = emisor |
| No es ERC-721 | Un certificado no debe transferirse; evitar complejidad de soulbound | ERC-721 con transfer bloqueado |
| Revocar no borra el registro (`revokedAt`) | Trazabilidad/auditoría; `verify` devuelve false | `delete` del certificado |
| Revocar: admin o emisor original *que aún tenga el rol* | Si se le quita el rol a un emisor, pierde todo poder | Cualquier emisor puede revocar |
| Un certificado vigente por (estudiante, curso); re-emisión permitida tras revocar | Evita duplicados pero permite corregir errores | Sin restricción |
| Errores personalizados (`error X()`) | Menos gas y revert reasons tipados en tests | `require` con strings |
| `courseId` como `bytes32` | Tamaño fijo, barato; se obtiene con `keccak256("COD")` | `string` |
| Ids secuenciales desde 1 (0 = inexistente) | Simple y barato | Hash como id |

## Estrategia de tests (`test/CertificateRegistry.t.sol`)
- **Unitarios**: camino feliz de emitir/revocar/verificar, estado almacenado, ids secuenciales.
- **Control de acceso**: extraños, admin sin rol de emisor, otro emisor, emisor al que se le quitó el rol.
- **Reverts**: dirección cero, hash vacío, duplicado, inexistente, doble revocación.
- **Eventos**: `vm.expectEmit` en emisión y revocación.
- **Fuzz**: entradas válidas arbitrarias, llamadores arbitrarios, conteo total.
- Extras sugeridos si hay tiempo: test de invariantes (`totalIssued` ≥ vigentes) y `forge coverage`.

## Frontend (complemento) — `frontend/`
React + Vite + viem, una sola página, conectada a Anvil (chainId 31337) con MetaMask.

**Incluye**
- Conexión de wallet y detección de rol (admin / emisor / sin rol) con `hasRole`.
- **Verificar (público, sin wallet):** `id` + archivo; el archivo se hashea (keccak256) en el navegador y se compara con `getCertificate`. Resultados: válido / revocado / no coincide / no existe.
- **Panel de emisor** (solo con `ISSUER_ROLE`): emitir (estudiante, código de curso -> `keccak256`, archivo) y revocar por id; muestra el `id` leído del evento `CertificateIssued`.
- **Panel de admin:** otorgar/quitar `ISSUER_ROLE`.
- Los reverts se decodifican con los errores personalizados del ABI (`AlreadyCertified(...)`, etc.).

**Fuera de alcance**: backend, base de datos, IPFS/subida de archivos, enrutamiento, estilos elaborados, tests de UI, despliegue web.

| Decisión | Por qué |
|---|---|
| Hash en el cliente | El documento nunca sale del navegador; on-chain solo va el hash. |
| Verificación vía RPC sin wallet | Un tercero (empleador) verifica sin instalar nada. |
| Mostrar paneles según rol | Solo UX: la seguridad real la impone el contrato (y la demuestran los tests). |
| ABI human-readable con `parseAbi` | Sin paso de build extra; incluye errores para decodificar reverts. |
| Sin backend | El contrato es la fuente de verdad. |

```bash
cd frontend && cp .env.example .env   # ajusta VITE_CONTRACT_ADDRESS con la dirección del deploy
npm install && npm run dev            # http://localhost:5173
```
En MetaMask: red personalizada `http://127.0.0.1:8545`, chainId `31337`, e importa una clave privada de Anvil.

## Comandos
```bash
# instalar Foundry: curl -L https://foundry.paradigm.xyz | bash && foundryup
forge init --force --no-git .          # si aún no hay lib/
forge install foundry-rs/forge-std OpenZeppelin/openzeppelin-contracts --no-git
forge build
forge test -vvv
forge coverage
anvil                                   # en otra terminal
forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
```
