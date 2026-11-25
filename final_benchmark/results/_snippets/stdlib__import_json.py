import json
print(json.dumps({'a': [1, 2, None, True], 'b': 1.5}))
print(json.loads('{"a": [1, 2, {"b": null}]}'))
