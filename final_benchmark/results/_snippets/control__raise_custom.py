class E(Exception):
    pass
try:
    raise E('boom')
except E as e:
    print('caught', e)
