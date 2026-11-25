# OOP: classes, attribute access, method calls, float physics + inheritance-free polymorphism by duck typing
import math

class Vec:
    def __init__(self, x, y):
        self.x = x
        self.y = y

    def length(self):
        return math.sqrt(self.x * self.x + self.y * self.y)

    def scale(self, k):
        self.x = self.x * k
        self.y = self.y * k

class Particle:
    def __init__(self, px, py, vx, vy):
        self.pos = Vec(px, py)
        self.vel = Vec(vx, vy)
        self.bounces = 0

    def step(self, dt):
        self.pos.x += self.vel.x * dt
        self.pos.y += self.vel.y * dt
        if self.pos.x < 0.0 or self.pos.x > 100.0:
            self.vel.x = -self.vel.x
            self.bounces += 1
        if self.pos.y < 0.0 or self.pos.y > 100.0:
            self.vel.y = -self.vel.y
            self.bounces += 1

    def energy(self):
        l = self.vel.length()
        return 0.5 * l * l

class Counter:
    def __init__(self):
        self.n = 0
    def inc(self, k):
        self.n += k

particles = []
x = 4242
for i in range(300):
    x = (x * 1103515245 + 12345) % 2147483648
    px = (x % 10000) / 100.0
    x = (x * 1103515245 + 12345) % 2147483648
    py = (x % 10000) / 100.0
    x = (x * 1103515245 + 12345) % 2147483648
    vx = (x % 2000) / 100.0 - 10.0
    x = (x * 1103515245 + 12345) % 2147483648
    vy = (x % 2000) / 100.0 - 10.0
    particles.append(Particle(px, py, vx, vy))

c = Counter()
for t in range(1000):
    for p in particles:
        p.step(0.01)
        c.inc(1)

total_bounces = 0
total_energy = 0.0
for p in particles:
    total_bounces += p.bounces
    total_energy += p.energy()
print("steps:", c.n)
print("bounces:", total_bounces)
print("energy:", round(total_energy, 6))
