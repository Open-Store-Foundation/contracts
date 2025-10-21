import {ethers} from "hardhat";
import {Contract, JsonRpcProvider, Interface, Log} from "ethers";
import http from "http";

type Publisher = {
    owner: string
    account: string
    name: string
}

type App = {
    appAddress: string
    id: string
    name: string
}

type Store = {
    owners: Map<string, Publisher>
    ownerToPublishers: Map<string, Set<string>>
    publisherToApps: Map<string, Map<string, App>>
}

const store: Store = {
    owners: new Map(),
    ownerToPublishers: new Map(),
    publisherToApps: new Map(),
}

let rpc: JsonRpcProvider

const FACTORY_ABI = [
    "event PublisherAccountCreated(address indexed owner, address account, string name)",
]

const APPS_PLUGIN_ABI = [
    "event AppCreated(address indexed appAddress, string id, string name)",
    "event AppTransferred(address indexed appAddress, address indexed oldOwner, address indexed newOwner)",
]

function parseArgs() {
    const args = process.argv.slice(2)
    const opts: Record<string, string> = {}
    for (let i = 0; i < args.length; i++) {
        const a = args[i]
        if (a.startsWith("--")) {
            const k = a.slice(2)
            const v = i + 1 < args.length && !args[i + 1].startsWith("--") ? args[++i] : "true"
            opts[k] = v
        }
    }
    return opts
}

function getPort() {
    const p = Number(opts.port || process.env.PORT || 3001)
    return Number.isFinite(p) ? p : 3001
}

function toChecksum(addr: string) {
    try {
        return ethers.getAddress(addr)
    } catch {
        return addr
    }
}

async function indexFactoryEvents(provider: JsonRpcProvider, factoryAddress: string) {
    const iface = new Interface(FACTORY_ABI)
    console.log(`[graph] Indexing factory at ${factoryAddress}`)
    const ev = iface.getEvent("PublisherAccountCreated")
    if (!ev) throw new Error("Event PublisherAccountCreated not found in iface")
    const topic = ev.topicHash
    const fromBlock = 0n
    const toBlock = "latest"

    const logs = await provider.getLogs({ address: factoryAddress, topics: [topic], fromBlock, toBlock })
    console.log(`[graph] Backfilled ${logs.length} PublisherAccountCreated`)
    for (const log of logs) {
        try { handlePublisherCreated(iface, log) } catch (e) { console.error(`[graph] backfill publisher error`, e) }
    }

    console.log(`[graph] Subscribed: PublisherAccountCreated -> ${factoryAddress}`)
    provider.on({ address: factoryAddress, topics: [topic] }, (log: Log) => {
        handlePublisherCreated(iface, log)
    })
}

function handlePublisherCreated(iface: Interface, log: Log) {
    try {
        const parsed = iface.parseLog({ topics: log.topics, data: log.data })
        if (!parsed) return
        const owner = toChecksum(parsed.args[0])
        const account = toChecksum(parsed.args[1])
        const name = String(parsed.args[2])
        console.log(`[graph] PublisherAccountCreated owner=${owner} account=${account} name=${name}`)

        store.owners.set(account, { owner, account, name })
        const key = owner.toLowerCase()
        let set = store.ownerToPublishers.get(key)
        if (!set) { set = new Set(); store.ownerToPublishers.set(key, set) }
        set.add(account)
        if (!store.publisherToApps.has(account)) {
            store.publisherToApps.set(account, new Map())
        }

        if (rpc) {
            subscribePublisherApps(rpc, account)
        }
    } catch {}
}

function subscribePublisherApps(provider: JsonRpcProvider, publisherAddress: string) {
    const iface = new Interface(APPS_PLUGIN_ABI)
    const evCreated = iface.getEvent("AppCreated")
    const evTransferred = iface.getEvent("AppTransferred")
    if (!evCreated || !evTransferred) throw new Error("App events not found in iface")
    const topicCreated = evCreated.topicHash
    const topicTransferred = evTransferred.topicHash

    const fromBlock = 0n
    console.log(`[graph] Subscribing apps for publisher ${publisherAddress}`)
    provider.getLogs({ address: publisherAddress, topics: [topicCreated], fromBlock, toBlock: "latest" })
        .then((logs) => { logs.forEach((l) => { try { handleAppCreated(publisherAddress, iface, l) } catch (e) { console.error(`[graph] backfill appCreated error`, e) } }); console.log(`[graph] Backfilled ${logs.length} AppCreated for ${publisherAddress}`) })
        .catch((e) => { console.error(`[graph] backfill AppCreated failed`, e) })
    provider.getLogs({ address: publisherAddress, topics: [topicTransferred], fromBlock, toBlock: "latest" })
        .then((logs) => { logs.forEach((l) => { try { handleAppTransferred(publisherAddress, iface, l) } catch (e) { console.error(`[graph] backfill appTransferred error`, e) } }); console.log(`[graph] Backfilled ${logs.length} AppTransferred for ${publisherAddress}`) })
        .catch((e) => { console.error(`[graph] backfill AppTransferred failed`, e) })

    provider.on({ address: publisherAddress, topics: [topicCreated] }, (l: Log) => handleAppCreated(publisherAddress, iface, l))
    provider.on({ address: publisherAddress, topics: [topicTransferred] }, (l: Log) => handleAppTransferred(publisherAddress, iface, l))
}

function handleAppCreated(publisher: string, iface: Interface, log: Log) {
    try {
        const parsed = iface.parseLog({ topics: log.topics, data: log.data })
        if (!parsed) return
        const appAddress = toChecksum(parsed.args[0])
        const id = String(parsed.args[1])
        const name = String(parsed.args[2])
        console.log(`[graph] AppCreated publisher=${publisher} app=${appAddress} id=${id} name=${name}`)

        let apps = store.publisherToApps.get(publisher)
        if (!apps) {
            apps = new Map()
            store.publisherToApps.set(publisher, apps)
        }
        apps.set(appAddress, { appAddress, id, name })
    } catch {}
}

function handleAppTransferred(publisher: string, iface: Interface, log: Log) {
    try {
        const parsed = iface.parseLog({ topics: log.topics, data: log.data })
        if (!parsed) return
        const appAddress = toChecksum(parsed.args[0])
        const oldOwner = toChecksum(parsed.args[1])
        const newOwner = toChecksum(parsed.args[2])
        console.log(`[graph] AppTransferred app=${appAddress} oldOwner=${oldOwner} newOwner=${newOwner}`)

        const oldApps = store.publisherToApps.get(oldOwner)
        if (oldApps && oldApps.has(appAddress)) {
            const app = oldApps.get(appAddress)!
            oldApps.delete(appAddress)
            let newApps = store.publisherToApps.get(newOwner)
            if (!newApps) {
                newApps = new Map()
                store.publisherToApps.set(newOwner, newApps)
            }
            newApps.set(appAddress, app)
        }
    } catch {}
}

function startHttpServer(port: number) {
    const server = http.createServer((req, res) => {
        if (!req.url) {
            res.statusCode = 404
            res.end()
            return
        }

        const url = new URL(req.url || '/', `http://localhost:${port}`)
        console.log(`[graph] ${req.method} ${url.pathname}`)
        res.setHeader("Content-Type", "application/json")
        res.setHeader("Access-Control-Allow-Origin", "*")
        res.setHeader("Access-Control-Allow-Methods", "GET, OPTIONS")
        res.setHeader("Access-Control-Allow-Headers", "Content-Type")

        if (req.method === "OPTIONS") {
            res.statusCode = 204
            res.end()
            return
        }

        if (req.method === "GET" && url.pathname.startsWith("/publishers/")) {
            const owner = url.pathname.split("/")[2] || ""
            const accountsSet = store.ownerToPublishers.get(owner.toLowerCase()) || new Set<string>()
            const accounts = Array.from(accountsSet).map((account) => {
                const pub = store.owners.get(account)
                return { name: pub?.name || "", address: account }
            })
            res.end(JSON.stringify({ accounts }))
            return
        }

        if (req.method === "GET" && url.pathname.startsWith("/apps/")) {
            const publisher = toChecksum(url.pathname.split("/")[2] || "")
            const apps = Array.from((store.publisherToApps.get(publisher) || new Map()).values()).map((a) => ({ id: a.appAddress, appId: a.id, name: a.name }))
            res.end(JSON.stringify({ apps }))
            return
        }

        res.statusCode = 404
        res.end(JSON.stringify({ error: "not_found" }))
    })

    server.listen(port, () => {
        console.log(`[graph] listening on ${port}`)
    })
}

const opts = parseArgs()

async function main() {
    const provider = ethers.provider as unknown as JsonRpcProvider
    rpc = provider
    const factory = String(opts.factory || process.env.FACTORY || "")
    if (!factory) {
        throw new Error("--factory <address> is required")
    }

    const net = await provider.getNetwork()
    console.log(`[graph] connected chainId=${net.chainId}`)
    await indexFactoryEvents(provider, toChecksum(factory))
    const port = getPort()
    console.log(`[graph] starting http on ${port}`)
    startHttpServer(port)
}

if (require.main === module) {
    main().catch((e) => {
        console.error(e)
        process.exit(1)
    })
}


