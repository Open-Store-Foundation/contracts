import {ethers} from "hardhat";
import {JsonRpcProvider, Interface, Log} from "ethers";
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
let factoryAddressGlobal = ""
let lastFactoryBlock = 0
const lastAppsBlockByPublisher = new Map<string, number>()

const FACTORY_ABI = [
    "event PublisherAccountCreated(address indexed owner, address account, string name)",
]

const APPS_PLUGIN_ABI = [
    "event AppCreated(address indexed appAddress, string id, string name)",
    "event AppTransferred(address indexed appAddress, address indexed oldOwner, address indexed newOwner)",
]

function getPort() {
    const p = Number(process.env.GRAPH_PORT || 3001)
    return Number.isFinite(p) ? p : 3001
}

function getFactory() {
    const factory = String(process.env.PUBLISHER_FACTORY || "")
    if (!factory) {
        throw new Error("process.env.PUBLISHER_FACTORY")
    }

    return factory
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
    const event = iface.getEvent("PublisherAccountCreated")
    if (!event) throw new Error("Event PublisherAccountCreated not found in iface")
    const topic = event.topicHash
    const fromBlock = 0n
    const toBlock = "latest"

    const logs = await provider.getLogs({ address: factoryAddress, topics: [topic], fromBlock, toBlock })
    console.log(`[graph] Backfilled ${logs.length} PublisherAccountCreated`)
    for (const log of logs) {
        try {
            handlePublisherCreated(iface, log, true)
        } catch (e) {
            console.error(`[graph] backfill publisher error`, e)
        }
    }
    let maxBlock = lastFactoryBlock
    for (const log of logs) {
        const bn: any = (log as any).blockNumber
        if (typeof bn === "number" && bn > maxBlock) maxBlock = bn
    }
    lastFactoryBlock = maxBlock
}

function handlePublisherCreated(iface: Interface, log: Log, doBackfillApps?: boolean) {
    try {
        const parsed = iface.parseLog({ topics: log.topics, data: log.data })
        if (!parsed) return
        const owner = toChecksum(parsed.args[0])
        const account = toChecksum(parsed.args[1])
        const name = String(parsed.args[2])
        console.log(`[graph] PublisherAccountCreated owner=${owner} account=${account} name=${name}`)

        store.owners.set(account, { owner, account, name })
        const key = owner.toLowerCase()
        let publishersForOwner = store.ownerToPublishers.get(key)
        if (!publishersForOwner) {
            publishersForOwner = new Set()
            store.ownerToPublishers.set(key, publishersForOwner)
        }
        publishersForOwner.add(account)

        if (!store.publisherToApps.has(account)) {
            store.publisherToApps.set(account, new Map())
        }
        if (doBackfillApps && rpc) {
            backfillPublisherApps(rpc, account)
        }
    } catch {}
}

async function backfillPublisherApps(provider: JsonRpcProvider, publisherAddress: string) {
    const iface = new Interface(APPS_PLUGIN_ABI)
    const evCreated = iface.getEvent("AppCreated")
    const evTransferred = iface.getEvent("AppTransferred")
    if (!evCreated || !evTransferred) throw new Error("App events not found in iface")
    const topicCreated = evCreated.topicHash
    const topicTransferred = evTransferred.topicHash
    const fromBlock = 0n
    const logsCreated = await provider.getLogs({ address: publisherAddress, topics: [topicCreated], fromBlock, toBlock: "latest" })
    logsCreated.forEach((l) => {
        try { handleAppCreated(publisherAddress, iface, l) } catch (e) { console.error(`[graph] backfill appCreated error`, e) }
    })
    const logsTransferred = await provider.getLogs({ address: publisherAddress, topics: [topicTransferred], fromBlock, toBlock: "latest" })
    logsTransferred.forEach((l) => {
        try { handleAppTransferred(publisherAddress, iface, l) } catch (e) { console.error(`[graph] backfill appTransferred error`, e) }
    })
    let maxBlock = lastAppsBlockByPublisher.get(publisherAddress) || 0
    for (const l of [...logsCreated, ...logsTransferred]) {
        const bn: any = (l as any).blockNumber
        if (typeof bn === "number" && bn > maxBlock) maxBlock = bn
    }
    lastAppsBlockByPublisher.set(publisherAddress, maxBlock)
}

async function refreshFactorySinceLast(provider: JsonRpcProvider, factoryAddress: string) {
    const iface = new Interface(FACTORY_ABI)
    const event = iface.getEvent("PublisherAccountCreated")
    if (!event) throw new Error("Event PublisherAccountCreated not found in iface")
    const topic = event.topicHash
    const fromBlock = lastFactoryBlock > 0 ? BigInt(lastFactoryBlock + 1) : 0n
    const logs = await provider.getLogs({ address: factoryAddress, topics: [topic], fromBlock, toBlock: "latest" })
    for (const log of logs) {
        try { handlePublisherCreated(iface, log, false) } catch {}
    }
    let maxBlock = lastFactoryBlock
    for (const log of logs) {
        const bn: any = (log as any).blockNumber
        if (typeof bn === "number" && bn > maxBlock) maxBlock = bn
    }
    lastFactoryBlock = maxBlock
}

async function refreshPublisherAppsSinceLast(provider: JsonRpcProvider, publisherAddress: string) {
    const iface = new Interface(APPS_PLUGIN_ABI)
    const evCreated = iface.getEvent("AppCreated")
    const evTransferred = iface.getEvent("AppTransferred")
    if (!evCreated || !evTransferred) throw new Error("App events not found in iface")
    const fromBlockStart = lastAppsBlockByPublisher.get(publisherAddress) || 0
    const fromBlock = fromBlockStart > 0 ? BigInt(fromBlockStart + 1) : 0n
    const topicCreated = evCreated.topicHash
    const topicTransferred = evTransferred.topicHash
    const logs = await rpc.getLogs({ address: publisherAddress, topics: [[topicCreated, topicTransferred]], fromBlock, toBlock: "latest" })
    for (const l of logs) {
        try {
            const t0 = l.topics?.[0]
            if (t0 === topicCreated) handleAppCreated(publisherAddress, iface, l)
            else if (t0 === topicTransferred) handleAppTransferred(publisherAddress, iface, l)
        } catch {}
    }
    let maxBlock = fromBlockStart
    for (const l of logs) {
        const bn: any = (l as any).blockNumber
        if (typeof bn === "number" && bn > maxBlock) maxBlock = bn
    }
    lastAppsBlockByPublisher.set(publisherAddress, maxBlock)
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
            refreshFactorySinceLast(rpc, factoryAddressGlobal)
                .then(() => {
                    const accountsSet = store.ownerToPublishers.get(owner.toLowerCase()) || new Set<string>()
                    const accounts = Array.from(accountsSet).map((account) => {
                        const pub = store.owners.get(account)
                        return { name: pub?.name || "", address: account }
                    })
                    res.end(JSON.stringify({ accounts }))
                })
                .catch(() => {
                    const accountsSet = store.ownerToPublishers.get(owner.toLowerCase()) || new Set<string>()
                    const accounts = Array.from(accountsSet).map((account) => {
                        const pub = store.owners.get(account)
                        return { name: pub?.name || "", address: account }
                    })
                    res.end(JSON.stringify({ accounts }))
                })
            return
        }

        if (req.method === "GET" && url.pathname.startsWith("/apps/")) {
            const publisher = toChecksum(url.pathname.split("/")[2] || "")
            refreshPublisherAppsSinceLast(rpc, publisher)
                .then(() => {
                    const apps = Array.from((store.publisherToApps.get(publisher) || new Map()).values()).map((a) => ({ id: a.appAddress, appId: a.id, name: a.name }))
                    res.end(JSON.stringify({ apps }))
                })
                .catch(() => {
                    const apps = Array.from((store.publisherToApps.get(publisher) || new Map()).values()).map((a) => ({ id: a.appAddress, appId: a.id, name: a.name }))
                    res.end(JSON.stringify({ apps }))
                })
            return
        }

        res.statusCode = 404
        res.end(JSON.stringify({ error: "not_found" }))
    })

    server.listen(port, () => {
        console.log(`[graph] listening on ${port}`)
    })
}

async function main() {
    const httpProvider = ethers.provider as unknown as JsonRpcProvider
    rpc = httpProvider

    const factory = getFactory()
    const net = await httpProvider.getNetwork()
    console.log(`[graph] connected chainId=${net.chainId}`)

    await indexFactoryEvents(httpProvider, toChecksum(factory))
    factoryAddressGlobal = toChecksum(factory)

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


