import jax.numpy as jnp
from jax import jacfwd

def block(x, W, b):
    return jnp.tanh(W @ x + b)

def block_with_jacobian(x, W, b):
    y = block(x, W, b)
    # Local Jacobian block: J[i,j] = dy_i / dx_j for this specific layer
    J = jacfwd(lambda xi: block(xi, W, b))(x)
    return y, J

def sequential_jacobian_blocks(x, layer_params):
    """
    Computes individual layer Jacobian blocks and propagates activations
    through a multi-layer stack.

    layer_params: list of tuples [(W1, b1), (W2, b2), ...]
    """
    activations = [x]
    jacobian_blocks = []

    current_x = x
    for W, b in layer_params:
        current_x, J_block = block_with_jacobian(current_x, W, b)
        activations.append(current_x)
        jacobian_blocks.append(J_block)

    return activations, jacobian_blocks

def compute_full_chain_jacobian(x, layer_params):
    """
    Computes the exact end-to-end network Jacobian via forward-mode AD
    or by multiplying the sequence of local Jacobian blocks via chain rule.
    """
    _, jacobian_blocks = sequential_jacobian_blocks(x, layer_params)

    # Chain rule composition: J_total = J_n @ J_{n-1} @ ... @ J_1
    J_total = jacobian_blocks[0]
    for J_block in jacobian_blocks[1:]:
        J_total = J_block @ J_total

    return J_total

# Example usage:
if __name__ == "__main__":
    key = jax.random.PRNGKey(0)
    dim = 4
    x = jax.random.normal(key, (dim,))

    # Define 3 sequential layers
    layer_params = [
        (jax.random.normal(jax.random.PRNGKey(1), (dim, dim)), jax.random.normal(jax.random.PRNGKey(2), (dim,))),
        (jax.random.normal(jax.random.PRNGKey(3), (dim, dim)), jax.random.normal(jax.random.PRNGKey(4), (dim,))),
        (jax.random.normal(jax.random.PRNGKey(5), (dim, dim)), jax.random.normal(jax.random.PRNGKey(6), (dim,)))
    ]

    activations, j_blocks = sequential_jacobian_blocks(x, layer_params)
    total_J = compute_full_chain_jacobian(x, layer_params)

    print("Layer Jacobian Block Shapes:", [j.shape for j in j_blocks])
    print("Composed Total Jacobian Shape:", total_J.shape)
