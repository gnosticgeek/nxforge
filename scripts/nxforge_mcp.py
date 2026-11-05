#!/usr/bin/env python3
# NXForge as an MCP server (Model Context Protocol, stdio transport): the functions of scripts/nxforge.py as tools an agent can call. Standard library only, so any python3 runs it.
# Register it with Claude Code:  claude mcp add nxforge -- python3 <checkout>/scripts/nxforge_mcp.py
# or in Claude Desktop's claude_desktop_config.json: {"mcpServers": {"nxforge": {"command": "python3", "args": ["<checkout>/scripts/nxforge_mcp.py"]}}}
# Deleting tools default to a dry run: nxforge_clean deletes only with dry_run false. A build runs in the background; nxforge_job follows it. docs/automation.md lists the tools.
import io, json, os, sys, contextlib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import nxforge as nx

PROTOCOL = '2025-06-18'
CATS = list(nx.CATEGORIES)


def obj(props=None, required=()):
    return {'type': 'object', 'properties': props or {}, 'required': list(required), 'additionalProperties': False}


SCOPE = {
    'categories': {'type': 'array', 'items': {'type': 'string', 'enum': CATS}, 'description': 'categories to report or clean; default the safe set: ' + ', '.join(nx.SAFE)},
    'game': {'type': 'string', 'description': 'only this game: its folder, its <id>_build folder or its title ID'},
    'backup_days': {'type': 'number', 'description': 'app-backups: only backups older than this many days (default 3)'},
    'backup_keep': {'type': 'integer', 'description': 'app-backups: newest backups kept per game (default 1)'},
    'log_days': {'type': 'number', 'description': 'old-logs: age in days (default 30)'},
    'metal_cache_gb': {'type': 'number', 'description': f'metal-cache: trim to this size (default {nx.MTLCACHE_GB:g})'},
}

TOOLS = [
    ('nxforge_status', 'Engine version, running builds and games, free disk space, recorded builds and running background jobs.', obj(), True),
    ('nxforge_builds', 'The game apps the converter built: path, whether it still exists, game folder, engine version, backups.', obj(), True),
    ('nxforge_doctor', 'Check the tools a build needs (engine checkout, Python modules, git, dotnet, xcrun).', obj(), True),
    ('nxforge_disk_report', 'What NXForge uses on disk (game folders, <id>_build folders, caches, checkouts) and what each cleanup category would free. Deletes nothing. '
     'Categories: ' + '; '.join(f'{k}{" [safe]" if s else ""}: {d}' for k, (d, s) in nx.CATEGORIES.items()), obj(dict(SCOPE, all={'type': 'boolean', 'description': 'every category, not only the safe ones'})), True),
    ('nxforge_clean', 'Delete what the given cleanup categories hold (default: the safe set, the one an hourly routine uses). dry_run defaults to true: pass dry_run false to delete. '
     'Never touches NSPs, keys, installed or recorded apps, saves or profiles; build-folder and Metal-cache categories are skipped while a build runs; refused while another cleanup runs. '
     'worktree removes one engine worktree, only when it is clean, pushed and not the engine.',
     obj(dict(SCOPE, dry_run={'type': 'boolean', 'description': 'list without deleting (default true)'}, worktree={'type': 'string', 'description': 'path of an engine worktree to remove'})), False),
    ('nxforge_build', "Build or rebuild a game's Mac app in the background, as the converter does; returns a job id for nxforge_job. plan true is the dry run that lists the stages that will be reused or redone.",
     obj({'game_dir': {'type': 'string', 'description': "the game's folder (NSPs, or a Switch 2 dump)"}, 'plan': {'type': 'boolean'},
          'rebuild': {'type': 'string', 'description': 'the existing app to replace (moved to app-backups/ first)'}, 'out': {'type': 'string'}, 'keys': {'type': 'string'},
          'cleanup': {'type': 'string', 'enum': ['off', 'unused', 'all']}}, ['game_dir']), False),
    ('nxforge_jobs', 'Background builds started through this interface, newest first.', obj(), True),
    ('nxforge_job', 'One background build: running or not, current stage, progress, result and the last log lines.', obj({'id': {'type': 'string'}, 'tail': {'type': 'integer'}}, ['id']), True),
    ('nxforge_stop_job', 'Stop a background build (as the converter\'s Stop button).', obj({'id': {'type': 'string'}}, ['id']), False),
    ('nxforge_update', 'Engine updates: fetch and list the commits waiting on its update branch; apply true fast-forwards (refused while a build runs or with uncommitted changes).',
     obj({'apply': {'type': 'boolean'}}), False),
]


def scope_ctx(a):
    return nx.context(game=a.get('game'), backup_days=a.get('backup_days'), backup_keep=a.get('backup_keep'), log_days=a.get('log_days'), mtlcache_gb=a.get('metal_cache_gb'))


def cats_of(a, default_all=False):
    c = a.get('categories') or (CATS if default_all else nx.SAFE)
    if bad := [x for x in c if x not in nx.CATEGORIES]: raise nx.Refused(f'unknown categories: {", ".join(bad)}')
    return c


def call(name, a):
    if name == 'nxforge_status': return nx.status()
    if name == 'nxforge_builds': return nx.builds_list()
    if name == 'nxforge_doctor': return nx.doctor()
    if name == 'nxforge_disk_report':
        ctx = scope_ctx(a)
        res = {'categories': nx.find(ctx, cats_of(a, a.get('all', False))), 'overview': nx.overview(ctx), 'free_bytes': nx.free_bytes()}
        for r in res['categories'].values(): [i.pop('files', None) for i in r['items']]
        res['would_free_bytes'] = sum(r.get('bytes', 0) for r in res['categories'].values())
        return res
    if name == 'nxforge_clean':
        cats = [] if a.get('worktree') and not a.get('categories') else cats_of(a)
        return nx.clean(cats, a.get('dry_run', True), scope_ctx(a), a.get('worktree'))
    if name == 'nxforge_build':
        return nx.start_job(a['game_dir'], **{k: a.get(k) for k in ('plan', 'rebuild', 'out', 'keys', 'cleanup')})
    if name == 'nxforge_jobs': return nx.list_jobs()
    if name == 'nxforge_job': return nx.job_state(a['id'], a.get('tail', 20))
    if name == 'nxforge_stop_job': return nx.stop_job(a['id'])
    if name == 'nxforge_update': return nx.update(a.get('apply', False))
    raise KeyError(name)


def handle(msg):
    """One JSON-RPC message → its response, or None for a notification"""
    mid, method, params = msg.get('id'), msg.get('method'), msg.get('params') or {}
    if mid is None: return None   # notifications/initialized, notifications/cancelled
    ok = lambda r: {'jsonrpc': '2.0', 'id': mid, 'result': r}
    if method == 'initialize':
        return ok({'protocolVersion': params.get('protocolVersion', PROTOCOL) if params.get('protocolVersion') in ('2024-11-05', '2025-03-26', PROTOCOL) else PROTOCOL,
                   'capabilities': {'tools': {}}, 'serverInfo': {'name': 'nxforge', 'version': (nx.engine(nx.find_repo()) or {}).get('version', '?')},
                   'instructions': 'NXForge: build Switch games as Mac apps and keep the disk clean. Start with nxforge_status or nxforge_disk_report; nxforge_clean deletes only with dry_run false.'})
    if method == 'ping': return ok({})
    if method == 'tools/list':
        return ok({'tools': [{'name': n, 'description': d, 'inputSchema': s, 'annotations': {'readOnlyHint': ro, 'destructiveHint': n in ('nxforge_clean', 'nxforge_build', 'nxforge_update')}}
                             for n, d, s, ro in TOOLS]})
    if method == 'tools/call':
        name, args = params.get('name'), params.get('arguments') or {}
        if name not in {t[0] for t in TOOLS}: return {'jsonrpc': '2.0', 'id': mid, 'error': {'code': -32602, 'message': f'unknown tool {name}'}}
        try:
            with contextlib.redirect_stdout(io.StringIO()):   # stdout is the protocol's: anything a function prints would corrupt it
                res = call(name, args)
            return ok({'content': [{'type': 'text', 'text': json.dumps(res, indent=1, default=str)}], 'isError': False})
        except (nx.Refused, OSError, KeyError, ValueError) as e:
            return ok({'content': [{'type': 'text', 'text': f'{type(e).__name__ if not isinstance(e, nx.Refused) else "refused"}: {e}'}], 'isError': True})
    return {'jsonrpc': '2.0', 'id': mid, 'error': {'code': -32601, 'message': f'method not found: {method}'}}


def main():
    out = sys.stdout
    for line in sys.stdin:
        line = line.strip()
        if not line: continue
        try: msg = json.loads(line)
        except ValueError:
            out.write(json.dumps({'jsonrpc': '2.0', 'id': None, 'error': {'code': -32700, 'message': 'parse error'}}) + '\n'); out.flush(); continue
        for m in msg if isinstance(msg, list) else [msg]:
            r = handle(m)
            if r is not None: out.write(json.dumps(r) + '\n'); out.flush()
    return 0


if __name__ == '__main__':
    os.environ.setdefault('PYTHONUNBUFFERED', '1')
    sys.exit(main())
