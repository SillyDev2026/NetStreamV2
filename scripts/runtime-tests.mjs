import {readFileSync, writeFileSync, mkdtempSync, rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {resolve, dirname, join} from 'node:path';
import {fileURLToPath} from 'node:url';
import {spawnSync} from 'node:child_process';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const read = path => readFileSync(join(root, path), 'utf8');
const temporary = mkdtempSync(join(tmpdir(), 'netstream-runtime-'));
// Run complete production modules; only Roblox services and test access are supplied here.
const source = read('Netstream.lua');
const end = source.lastIndexOf('return NetStream');
if (end < 0) throw new Error('Module return missing');
const hooks = `
NetStream.__test = {
    players = Players,
    register = function(id, callback) functionRoutes[id] = {_callback = callback} end,
    registerFunction = function(id, route) functionRoutes[id] = route end,
    registerEvent = function(id, route) eventRoutes[id] = route end,
    registerState = function(id, route) stateRoutes[id] = route end,
    allowance = consumeRouteAllowance,
    stateGet = StateRoute.Get,
    dispatch = dispatchRoute,
    dispatchScalar = dispatchRouteScalar,
    charge = Internal.chargeIncomingCall,
    run = Internal.runIncomingCall,
}
`;
const bootstrap = `
local Compression = (function()
${read('Compression.lua')}
end)()
local function loadNetStream()
    local services = {RunService = {IsServer = function() return true end}, ReplicatedStorage = {}, Players = {}}
    local nativeTypeof = typeof
    local typeof = function(value) return if type(value) == "table" and value.__player then "Instance" else nativeTypeof(value) end
    local game = {GetService = function(_, name) return assert(services[name], name) end}
    local script = {WaitForChild = function() return Compression end}
    local require = function(module) return module end
    local Random = {new = function() return {NextInteger = function(_, low) return low end} end}
    local warn = function() end
    local task = setmetatable({defer = function() end}, {__index = function(_, key) error('Unexpected scheduler use: ' .. key) end})
    ${source.slice(0, end)}
    ${hooks}
    return NetStream
end
`;
try {
    const suites = process.argv.includes('--stress-only') ? ['server_stress'] : ['codec', 'delta', 'rpc', 'security', 'tickets'];
    for (const suite of suites) {
        const path = join(temporary, suite + '.luau');
        writeFileSync(path, bootstrap + '\n' + read(`tests/runtime/${suite}.luau`));
        const result = spawnSync(process.env.LUAU_BIN || 'luau', [path], {stdio: 'inherit'});
        if (result.error) throw result.error;
        if (result.status !== 0) process.exitCode = 1;
    }
} finally {
    rmSync(temporary, {recursive: true, force: true});
}
