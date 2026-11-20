# Test classes, OOP, inheritance, attributes

class Shape:
    def __init__(self, name):
        self.name = name

    def area(self):
        return 0

class Rectangle(Shape):
    def __init__(self, width, height):
        self.name = "Rectangle"
        self.width = width
        self.height = height

    def area(self):
        return self.width * self.height

class Square(Rectangle):
    def __init__(self, side):
        self.name = "Square"
        self.width = side
        self.height = side

r = Rectangle(10, 5)
print("Shape:", r.name)
print("Rectangle area (10x5):", r.area())

sq = Square(7)
print("Shape:", sq.name)
print("Square area (7x7):", sq.area())

print("isinstance sq Square:", isinstance(sq, Square))
print("isinstance sq Rectangle:", isinstance(sq, Rectangle))
print("isinstance sq Shape:", isinstance(sq, Shape))
print("OOP tests passed successfully!")
