# Test control flow: if/elif/else, while, for, break, continue

print("--- If/Elif/Else ---")
score = 85
if score >= 90:
    grade = "A"
elif score >= 80:
    grade = "B"
elif score >= 70:
    grade = "C"
else:
    grade = "F"
print("Score 85 grade:", grade)

print("--- While Loop with Break/Continue ---")
count = 0
sum_even = 0
while count < 10:
    count += 1
    if count % 2 != 0:
        continue
    if count == 8:
        break
    sum_even += count
print("Sum of even numbers before 8:", sum_even)

print("--- For Loop & Range ---")
squares = []
for i in range(5):
    squares.append(i * i)
print("Squares 0..4:", squares)
print("Control tests passed successfully!")
