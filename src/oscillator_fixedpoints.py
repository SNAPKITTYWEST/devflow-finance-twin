#!/usr/bin/env python3
# oscillator_fixedpoints.py
# Numeric attractor search for the Hopf oscillator network over symbol coordinates.

import numpy as np
from scipy.spatial.distance import cdist
from scipy.cluster.vq import kmeans2

coords = np.array([
 [ 0.0,  0.0],  # mandala
 [ 1.2,  0.4],  # tower
 [ 1.0,  0.1],  # stone
 [-0.8,  0.9],  # sun
 [-0.6,  0.6],  # star
 [ 0.2, -0.9],  # dream_door_room
 [ 0.9, -0.6],  # snake
 [-0.4,  0.2],  # chalice
 [ 0.3, -0.4],  # fire
 [-0.2,  0.7],  # anima_mundi
 [-0.1,  0.4],  # alchemy
 [-0.3,  0.5],  # light_dark
 [ 0.0,  0.6],  # gates
 [ 0.3, -1.1],  # room
 [ 0.0,  0.3],  # opposites
])

N     = coords.shape[0]
alpha = 1.0
dt    = 0.05
kappa = 0.6
sigma = 0.9

d2 = cdist(coords, coords, 'sqeuclidean')
K  = kappa * np.exp(-d2 / (sigma**2))

counts = np.array([3,4,2,2,1,4,1,1,1,1,2,2,1,4,2], dtype=float)
F      = 0.2 * (counts / counts.sum())

def step(z):
    nonl = (alpha - np.abs(z)**2) * z
    coup = np.array([np.sum(K[i,:] * (z - z[i])) for i in range(N)])
    return z + dt * (nonl + coup + F.astype(complex))

def find_attractors(num_inits=200, steps=2000, tol=1e-6):
    attractors = []
    for s in range(num_inits):
        z = 0.1 * (np.random.randn(N) + 1j*np.random.randn(N))
        for t in range(steps):
            z_next = step(z)
            if np.max(np.abs(z_next - z)) < tol:
                z = z_next
                break
            z = z_next
        attractors.append(np.hstack([z.real, z.imag]))
    A = np.vstack(attractors)
    centroids, labels = kmeans2(A, min(10, len(A)), iter=20)
    return centroids, labels

if __name__ == "__main__":
    centroids, labels = find_attractors()
    print(f"Found {len(np.unique(labels))} attractor centroids from shape {centroids.shape}")
