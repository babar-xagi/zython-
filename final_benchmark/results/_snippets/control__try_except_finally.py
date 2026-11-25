try:
    1 // 0
except ZeroDivisionError as e:
    print('zde', e)
finally:
    print('fin')
