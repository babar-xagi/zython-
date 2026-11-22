import time

print("==========================================")
print("TEST 3: OBJECT-ORIENTED PROGRAMMING & INHERITANCE")
print("==========================================")

class Vector2D:
    def __init__(self, x, y):
        self.x = x
        self.y = y

    def length_squared(self):
        return self.x * self.x + self.y * self.y

    def scale(self, factor):
        self.x = self.x * factor
        self.y = self.y * factor

def run_small_oop():
    t0 = time.time()
    total_len_sq = 0
    for i in range(50000):
        vec = Vector2D(i, i + 1)
        vec.scale(2)
        total_len_sq += vec.length_squared()
    t1 = time.time()
    print("1. Small OOP (<=4 attributes, 50k instances): Result =", total_len_sq, "| Time:", round(t1 - t0, 5), "s")

class Entity:
    def __init__(self, name, x, y):
        self.name = name
        self.x = x
        self.y = y

    def get_role(self):
        return "Generic Entity"

class Character(Entity):
    def __init__(self, name, x, y, hp):
        self.name = name
        self.x = x
        self.y = y
        self.hp = hp

    def get_role(self):
        return "Character"

    def take_damage(self, dmg):
        self.hp -= dmg
        return self.hp

class Player(Character):
    def __init__(self, name, x, y, hp, mana):
        self.name = name
        self.x = x
        self.y = y
        self.hp = hp
        self.mana = mana

    def get_role(self):
        return "Player"

    def cast_spell(self, cost):
        if self.mana >= cost:
            self.mana -= cost
            return True
        return False

def run_polymorphic_oop():
    t0 = time.time()
    alive_count = 0
    mana_spent = 0
    for i in range(25000):
        p = Player("Hero", i, i, 100, 50)
        p.take_damage(35)
        if p.cast_spell(20):
            mana_spent += 20
        if p.hp > 0:
            alive_count += 1
    t1 = time.time()
    print("2. Polymorphic Hierarchy (3 levels, 25k instances): Alive =", alive_count, "Mana =", mana_spent, "| Time:", round(t1 - t0, 5), "s")

class HeavyEntity:
    def __init__(self, val):
        self.f1 = val
        self.f2 = val + 1
        self.f3 = val + 2
        self.f4 = val + 3
        self.f5 = val + 4
        self.f6 = val + 5
        self.f7 = val + 6
        self.f8 = val + 7
        self.f9 = val + 8
        self.f10 = val + 9

    def sum_all(self):
        return self.f1 + self.f2 + self.f3 + self.f4 + self.f5 + self.f6 + self.f7 + self.f8 + self.f9 + self.f10

def run_heavy_oop():
    t0 = time.time()
    heavy_sum = 0
    for i in range(15000):
        he = HeavyEntity(i)
        heavy_sum += he.sum_all()
    t1 = time.time()
    print("3. Heavy Object (>8 attributes, 15k instances): Sum =", heavy_sum, "| Time:", round(t1 - t0, 5), "s")

run_small_oop()
run_polymorphic_oop()
run_heavy_oop()
print("OOP benchmark complete.")
