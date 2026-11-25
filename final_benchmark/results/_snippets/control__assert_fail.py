try:
    assert 1 == 2, 'msg'
except AssertionError as e:
    print('ae', e)
