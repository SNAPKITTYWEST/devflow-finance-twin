%% transformer_forward_fixed.m
% Fixed-point transformer forward pass with Weyl deformation layer.
% Domain: D=768, q=32, p=3, vocab=32000, seq_len=16.
% Decoding: Mode A (greedy, deterministic) and Mode B (phase-biased sampling).

function transformer_forward_fixed()

    %% Domain parameters
    D       = 768;
    q       = 32;
    p       = 3;
    vocab   = 32000;
    seq_len = 16;
    gamma   = 0.1;
    theta0  = 3/32;
    rng(42);

    %% Weyl clock-shift pair U, V with relation V*U = omega * U*V
    omega = exp(2i*pi*p/q);
    U = diag(omega.^(0:q-1));
    V = zeros(q);
    for i = 0:q-1
        V(i+1, mod(i+1,q)+1) = 1;
    end
    assert(norm(V*U - omega*(U*V), 'fro') < 1e-10);

    %% Deformation matrix D_theta from normalized Weyl-basis coefficients
    C = randn(q,q) + 1i*randn(q,q);
    C = C / norm(C,'fro');
    D_theta = zeros(q);
    for k = 0:q-1
        for m = 0:q-1
            D_theta = D_theta + C(k+1,m+1) * (omega^(k*m)) * (U^k) * (V^m);
        end
    end

    %% Weight initialization
    W_emb  = randn(vocab, D) / sqrt(D);
    W_q    = randn(D, D)     / sqrt(D);
    W_k    = randn(D, D)     / sqrt(D);
    W_v    = randn(D, D)     / sqrt(D);
    W_o    = randn(D, D)     / sqrt(D);
    W_gate = randn(2*D, D)   / sqrt(D);
    W_down = randn(D, 2*D)   / sqrt(D);
    W_head = randn(vocab, D) / sqrt(D);
    g_attn  = ones(D,1);
    g_mlp   = ones(D,1);
    g_final = ones(D,1);

    %% Input
    input_tokens = randi([1, vocab], 1, seq_len);
    X = W_emb(input_tokens, :);    % [seq_len, D]

    %% KV cache and per-position forward pass
    Kc          = zeros(seq_len, D);
    Vc          = zeros(seq_len, D);
    logits_all  = zeros(seq_len, vocab);

    for t = 1:seq_len
        x  = X(t,:)';                       % [D,1]
        xn = rmsnorm(x, g_attn);

        k_vec  = W_k * xn;
        v_vec  = W_v * xn;
        Kc(t,:) = k_vec.';
        Vc(t,:) = v_vec.';

        q_vec = W_q * xn;

        %% Weyl deformation applied to first 2q components of q_vec
        z_q        = q_vec(1:q) + 1i*q_vec(q+1:2*q);
        z_q_tilde  = D_theta * z_q;
        q_vec(1:q)        = real(z_q_tilde);
        q_vec(q+1:2*q)    = imag(z_q_tilde);

        %% Causal attention over positions 1..t
        scores = (Kc(1:t,:) * q_vec) / sqrt(D);   % [t,1]
        attn   = stable_softmax(scores);
        ctx    = (attn.' * Vc(1:t,:)).';           % [D,1]

        x = x + W_o * ctx;

        %% FFN with SwiGLU
        xn2      = rmsnorm(x, g_mlp);
        mlp_gate = W_gate * xn2;                  % [2D,1]
        g_val    = mlp_gate(1:D);
        u_val    = mlp_gate(D+1:2*D);
        swiglu   = (g_val .* stable_sigmoid(g_val)) .* u_val;
        x = x + W_down * swiglu;

        xf              = rmsnorm(x, g_final);
        logits_all(t,:) = (W_head * xf).';
    end

    %% Decoding
    logits = logits_all(end, :);

    % Mode A: greedy (deterministic)
    [~, tok_greedy] = max(logits);

    % Mode B: phase-biased sampling with eta_t noise
    eta_t   = randn(q,1);
    z_q_last = W_q * rmsnorm(X(end,:)', g_attn);
    z_q_last = z_q_last(1:q) + 1i*z_q_last(q+1:2*q);
    theta_raw     = mod(theta0 + gamma*real(eta_t' * conj(z_q_last)), 1);
    p_t           = mod(round(q * theta_raw), q);
    logits_biased = logits;
    logits_biased(mod(p_t+1, vocab)+1) = logits_biased(mod(p_t+1, vocab)+1) + 5.0;
    [~, tok_phase] = max(logits_biased);

    fprintf('greedy token      : %d\n', tok_greedy - 1);
    fprintf('phase-biased token: %d  (p_t=%d)\n', tok_phase - 1, p_t);
end

%% ────────────────────────────────────────────────────────────────────
%% init_deformation.m
% Concrete Weyl deformation initialization.
% D=768, q=32, p=3, theta=3/32.
% Does not attempt superposition unfolding or PRNG inversion.

function init_deformation()

    D      = 768;
    q      = 32;
    p      = 3;
    gamma  = 0.1;
    theta0 = 3/32;
    fprintf('domain: D=%d, q=%d, p=%d, theta=%d/%d\n', D, q, p, p, q);

    %% Clock-shift pair with Weyl relation V*U = omega*U*V
    omega = exp(2i * pi * p / q);
    U = diag(omega .^ (0:q-1));
    V = zeros(q);
    for i = 0:q-1
        V(i+1, mod(i+1,q)+1) = 1;
    end
    assert(norm(V*U - omega*(U*V), 'fro') < 1e-10);
    fprintf('VU = omega UV : OK\n');

    %% Weyl basis K_{k,m} = omega^{km} U^k V^m
    K  = cell(q, q);
    Uk = eye(q);
    for k = 0:q-1
        Vm = eye(q);
        for m = 0:q-1
            K{k+1,m+1} = (omega^(k*m)) * (Uk * Vm);
            Vm = Vm * V;
        end
        Uk = Uk * U;
    end

    %% Orthonormality check: trace(K_{k,m}' * K_{k2,m2}) / q = delta
    G  = zeros(q*q, q*q);
    r1 = 0;
    for k = 0:q-1
        for m = 0:q-1
            r1 = r1 + 1; r2 = 0;
            for k2 = 0:q-1
                for m2 = 0:q-1
                    r2      = r2 + 1;
                    G(r1,r2)= trace(K{k+1,m+1}' * K{k2+1,m2+1}) / q;
                end
            end
        end
    end
    assert(norm(G - eye(q*q), 'fro') < 1e-8);
    fprintf('Weyl basis orthonormal : OK\n');

    %% Deformation matrix from normalized coefficients
    rng(1);
    C       = (randn(q,q) + 1i*randn(q,q));
    C       = C / norm(C,'fro');
    D_theta = zeros(q,q);
    for k = 0:q-1
        for m = 0:q-1
            D_theta = D_theta + C(k+1,m+1) * K{k+1,m+1};
        end
    end
    assert(isequal(size(D_theta), [q,q]));
    fprintf('D_theta initialized: %dx%d complex, ||D||_F = %.4f\n', ...
            q, q, norm(D_theta,'fro'));

    %% Projection stub: real x in R^D -> complex z in C^q -> apply D_theta
    W_in  = (randn(2*q,D) + 1i*randn(2*q,D)) / sqrt(2*D);
    W_out = randn(D, 2*q) / sqrt(2*q);
    x     = randn(D,1);
    h     = W_in * x;
    z     = h(1:q) + 1i*h(q+1:2*q);
    z_tilde = D_theta * z;
    y       = W_out * [real(z_tilde); imag(z_tilde)];
    fprintf('projection round-trip: ||y|| = %.4f\n', norm(y));

    %% Theta modulation (not PRNG inversion)
    eta_t     = randn(q,1);
    zbar_t    = conj(z);
    theta_raw = mod(theta0 + gamma * real(eta_t' * zbar_t), 1);
    p_t       = mod(round(q * theta_raw), q);
    fprintf('theta_raw=%.6f -> p_t=%d\n', theta_raw, p_t);

    %% Greedy decoding stub
    vocab  = 32000;
    logits = randn(1, vocab);
    [~, tok] = max(logits);
    fprintf('greedy token: %d\n', tok - 1);
    fprintf('init complete\n');
end

%% ────────────────────────────────────────────────────────────────────
%% Helper functions

function y = rmsnorm(x, g)
    rms = sqrt(mean(x.^2) + 1e-6);
    y   = (x ./ rms) .* g;
end

function y = stable_softmax(s)
    m = max(s);
    e = exp(s - m);
    y = e / sum(e);
end

function y = stable_sigmoid(x)
    if x >= 0
        y = 1 / (1 + exp(-x));
    else
        ex = exp(x);
        y  = ex / (1 + ex);
    end
end
