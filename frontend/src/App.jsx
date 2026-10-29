import { useCallback, useEffect, useState } from 'react'
import {
  createWalletClient,
  custom,
  keccak256,
  stringToHex,
  isAddress,
  parseEventLogs,
  BaseError,
  ContractFunctionRevertedError,
} from 'viem'
import { foundry } from 'viem/chains'
import { abi, publicClient, CONTRACT_ADDRESS } from './contract.js'

const base = { address: CONTRACT_ADDRESS, abi }

const hashFile = async (file) => keccak256(new Uint8Array(await file.arrayBuffer()))
const courseToId = (code) => keccak256(stringToHex(code.trim()))
const fmtDate = (ts) => (ts ? new Date(Number(ts) * 1000).toLocaleString() : '—')

// Convierte un revert del contrato en un mensaje legible usando los errores del ABI.
function errorMessage(e) {
  if (e instanceof BaseError) {
    const revert = e.walk((err) => err instanceof ContractFunctionRevertedError)
    if (revert instanceof ContractFunctionRevertedError && revert.data) {
      return `${revert.data.errorName}(${(revert.data.args ?? []).join(', ')})`
    }
    return e.shortMessage
  }
  return String(e)
}

function Section({ title, children }) {
  return (
    <section style={{ border: '1px solid #ccc', borderRadius: 8, padding: 16, marginBottom: 16 }}>
      <h2 style={{ marginTop: 0 }}>{title}</h2>
      {children}
    </section>
  )
}

function Result({ result }) {
  if (!result) return null
  const color = result.ok ? '#0a7a2f' : '#b00020'
  return <pre style={{ color, whiteSpace: 'pre-wrap', wordBreak: 'break-all' }}>{result.text}</pre>
}

function Verify() {
  const [id, setId] = useState('')
  const [file, setFile] = useState(null)
  const [result, setResult] = useState(null)

  const submit = async (e) => {
    e.preventDefault()
    try {
      const hash = await hashFile(file)
      const [cert, valid] = await publicClient.readContract({ ...base, functionName: 'getCertificate', args: [BigInt(id)] })
      const matches = hash === cert.documentHash
      const status = !matches ? 'NO COINCIDE: el archivo fue alterado o es de otro certificado' : valid ? 'VÁLIDO' : 'REVOCADO'
      setResult({
        ok: matches && valid,
        text: [
          status,
          `Estudiante: ${cert.student}`,
          `Emisor: ${cert.issuer}`,
          `Curso (id): ${cert.courseId}`,
          `Emitido: ${fmtDate(cert.issuedAt)}`,
          `Revocado: ${fmtDate(cert.revokedAt)}`,
        ].join('\n'),
      })
    } catch (err) {
      setResult({ ok: false, text: errorMessage(err) })
    }
  }

  return (
    <Section title="Verificar certificado (público)">
      <form onSubmit={submit}>
        <input type="number" min="1" placeholder="ID del certificado" value={id} onChange={(e) => setId(e.target.value)} required />{' '}
        <input type="file" onChange={(e) => setFile(e.target.files[0])} required />{' '}
        <button type="submit">Verificar</button>
      </form>
      <p style={{ fontSize: 12, color: '#666' }}>El archivo se hashea en tu navegador; no se sube a ningún servidor.</p>
      <Result result={result} />
    </Section>
  )
}

function Issue({ wallet, account }) {
  const [student, setStudent] = useState('')
  const [course, setCourse] = useState('')
  const [file, setFile] = useState(null)
  const [result, setResult] = useState(null)
  const [revokeId, setRevokeId] = useState('')
  const [revokeResult, setRevokeResult] = useState(null)

  const send = async (functionName, args) => {
    const { request } = await publicClient.simulateContract({ ...base, functionName, args, account })
    const hash = await wallet.writeContract(request)
    return publicClient.waitForTransactionReceipt({ hash })
  }

  const issue = async (e) => {
    e.preventDefault()
    try {
      if (!isAddress(student)) throw new Error('Dirección de estudiante inválida')
      const receipt = await send('issueCertificate', [student, courseToId(course), await hashFile(file)])
      const [log] = parseEventLogs({ abi, logs: receipt.logs, eventName: 'CertificateIssued' })
      setResult({ ok: true, text: `Certificado emitido. ID = ${log.args.id}\ntx: ${receipt.transactionHash}` })
    } catch (err) {
      setResult({ ok: false, text: errorMessage(err) })
    }
  }

  const revoke = async (e) => {
    e.preventDefault()
    try {
      const receipt = await send('revokeCertificate', [BigInt(revokeId)])
      setRevokeResult({ ok: true, text: `Revocado. tx: ${receipt.transactionHash}` })
    } catch (err) {
      setRevokeResult({ ok: false, text: errorMessage(err) })
    }
  }

  return (
    <Section title="Panel de emisor">
      <form onSubmit={issue}>
        <input placeholder="Dirección del estudiante (0x…)" value={student} onChange={(e) => setStudent(e.target.value)} size={44} required />{' '}
        <input placeholder="Código del curso (ej. SOLIDITY-101)" value={course} onChange={(e) => setCourse(e.target.value)} required />{' '}
        <input type="file" onChange={(e) => setFile(e.target.files[0])} required />{' '}
        <button type="submit">Emitir</button>
      </form>
      <Result result={result} />
      <hr />
      <form onSubmit={revoke}>
        <input type="number" min="1" placeholder="ID a revocar" value={revokeId} onChange={(e) => setRevokeId(e.target.value)} required />{' '}
        <button type="submit">Revocar</button>
      </form>
      <Result result={revokeResult} />
    </Section>
  )
}

function Admin({ wallet, account }) {
  const [target, setTarget] = useState('')
  const [result, setResult] = useState(null)

  const setRole = async (functionName) => {
    try {
      if (!isAddress(target)) throw new Error('Dirección inválida')
      const role = await publicClient.readContract({ ...base, functionName: 'ISSUER_ROLE' })
      const { request } = await publicClient.simulateContract({ ...base, functionName, args: [role, target], account })
      const hash = await wallet.writeContract(request)
      await publicClient.waitForTransactionReceipt({ hash })
      setResult({ ok: true, text: `${functionName} ejecutado. tx: ${hash}` })
    } catch (err) {
      setResult({ ok: false, text: errorMessage(err) })
    }
  }

  return (
    <Section title="Panel de administrador (emisores)">
      <input placeholder="Dirección (0x…)" value={target} onChange={(e) => setTarget(e.target.value)} size={44} />{' '}
      <button onClick={() => setRole('grantRole')}>Otorgar ISSUER_ROLE</button>{' '}
      <button onClick={() => setRole('revokeRole')}>Quitar ISSUER_ROLE</button>
      <Result result={result} />
    </Section>
  )
}

export default function App() {
  const [account, setAccount] = useState(null)
  const [wallet, setWallet] = useState(null)
  const [roles, setRoles] = useState({ admin: false, issuer: false })
  const [error, setError] = useState(null)

  const loadRoles = useCallback(async (addr) => {
    const [adminRole, issuerRole] = await Promise.all([
      publicClient.readContract({ ...base, functionName: 'DEFAULT_ADMIN_ROLE' }),
      publicClient.readContract({ ...base, functionName: 'ISSUER_ROLE' }),
    ])
    const [admin, issuer] = await Promise.all([
      publicClient.readContract({ ...base, functionName: 'hasRole', args: [adminRole, addr] }),
      publicClient.readContract({ ...base, functionName: 'hasRole', args: [issuerRole, addr] }),
    ])
    setRoles({ admin, issuer })
  }, [])

  const connect = async () => {
    try {
      if (!window.ethereum) throw new Error('No se encontró una wallet (instala MetaMask)')
      const client = createWalletClient({ chain: foundry, transport: custom(window.ethereum) })
      const [addr] = await client.requestAddresses()
      setWallet(client)
      setAccount(addr)
      setError(null)
    } catch (err) {
      setError(errorMessage(err))
    }
  }

  useEffect(() => {
    if (account) loadRoles(account).catch((err) => setError(errorMessage(err)))
  }, [account, loadRoles])

  useEffect(() => {
    if (!window.ethereum?.on) return
    const onChange = ([addr]) => setAccount(addr ?? null)
    window.ethereum.on('accountsChanged', onChange)
    return () => window.ethereum.removeListener('accountsChanged', onChange)
  }, [])

  if (!CONTRACT_ADDRESS) {
    return <p style={{ padding: 24 }}>Falta VITE_CONTRACT_ADDRESS. Copia <code>.env.example</code> a <code>.env</code>.</p>
  }

  const roleLabel = roles.admin ? 'admin' : roles.issuer ? 'emisor' : 'sin rol'

  return (
    <main style={{ maxWidth: 820, margin: '0 auto', padding: 24, fontFamily: 'system-ui, sans-serif' }}>
      <h1>Certificate Registry</h1>
      <p>
        {account ? <>Cuenta: <code>{account}</code> — rol: <b>{roleLabel}</b></> : <button onClick={connect}>Conectar wallet</button>}
      </p>
      {error && <p style={{ color: '#b00020' }}>{error}</p>}
      <Verify />
      {account && roles.issuer && <Issue wallet={wallet} account={account} />}
      {account && roles.admin && <Admin wallet={wallet} account={account} />}
    </main>
  )
}
