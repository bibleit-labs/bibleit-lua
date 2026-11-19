#!/usr/bin/env python3
"""Regenerate portable Lua metadata from the checked-in canonical OpenAPI.

Optionally supply the server OpenAPI path to refresh contract/openapi.json first.
The SDK only exposes operations assigned to the pinned public REST origin.
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
contract = ROOT / "contract/openapi.json"
if len(sys.argv) > 1:
    contract.write_bytes(Path(sys.argv[1]).read_bytes())
spec = json.loads(contract.read_text())


def string(value):
    return '"' + ''.join('\\"' if c == '"' else '\\\\' if c == '\\' else
                         '\\%03d' % ord(c) if ord(c) < 32 else c for c in value) + '"'


def lua(value):
    if value is None:
        return 'require("dkjson").null'
    if isinstance(value, bool):
        return str(value).lower()
    if isinstance(value, str):
        return string(value)
    if isinstance(value, list):
        return 'setmetatable({ ' + ', '.join(map(lua, value)) + ' }, array_mt)'
    if isinstance(value, dict):
        return '{ ' + ', '.join('[' + string(k) + '] = ' + lua(v) for k, v in sorted(value.items())) + ' }'
    return str(value)


operations = {}
for path, item in spec['paths'].items():
    for method, operation in item.items():
        if isinstance(operation, dict) and operation.get('x-fern-server-name') == 'rest':
            operations[operation['operationId']] = dict(method=method.upper(), path=path,
                parameters=re.findall(r'\{([^}]+)\}', path), summary=operation.get('summary', ''))
for name, metadata in [('operations', operations), ('schemas', spec['components']['schemas'])]:
    lines = ['-- Generated from contract/openapi.json. Do not edit.',
             'local array_mt = { __jsontype = "array" }', 'return {']
    lines += ['   [' + string(k) + '] = ' + lua(v) + ',' for k, v in sorted(metadata.items())]
    lines.append('}')
    (ROOT / ('src/bibleit/internal/' + name + '_generated.lua')).write_text('\n'.join(lines) + '\n')

inventory = ROOT / 'docs/api-parity.md'
text = inventory.read_text()
rows = ['| Operation ID | HTTP | Path | Status |', '| --- | --- | --- | --- |']
rows += [f"| `{k}` | {v['method']} | `{v['path']}` | Implemented |" for k, v in sorted(operations.items())]
text = re.sub(r'## REST operations \(\d+\)\n\n.*?(?=\n## )',
              '## REST operations (' + str(len(operations)) + ')\n\n' + '\n'.join(rows) + '\n', text, count=1, flags=re.S)
inventory.write_text(text)
print(f"Generated {len(operations)} REST operations and {len(spec['components']['schemas'])} schemas")
