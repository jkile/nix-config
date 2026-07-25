# Local LLM inference on the R9700, plus the Qwen Code CLI that drives it.
# Desktop-only (imported by ./default.nix) because every number in here is sized
# to this machine's GPU: 32 GB of VRAM on a Navi 48.
#
# Shape of the setup: one llama-server in *router* mode, and `qwen` wrapped to
# point at it. Nothing starts at boot — running `qwen` brings the service up,
# and it releases the GPU again after 15 min idle. Two layers of laziness, which
# matters on a box that also runs Steam:
#   - the unit isn't started until something wants it (see wantedBy below)
#   - once started, the router holds no model until a request names one
{
  pkgs,
  lib,
  ...
}:

let
  # Vulkan (RADV) rather than ROCm: RDNA4 (gfx1201) ROCm support is still
  # stabilizing, and the Vulkan path needs no extra driver config — RADV already
  # comes from hardware.graphics in ./default.nix. Bound to a let-binding because
  # both the service and the CLI tools have to be the *same* build; pointing
  # services.llama-cpp.package at a plain pkgs.llama-cpp would silently give you
  # a CPU-only server.
  llamaCppVulkan = pkgs.llama-cpp.override { vulkanSupport = true; };

  port = 8080;

  # The router publishes each preset under its INI section name *and* its alias
  # (verified against `GET /v1/models`). qwen-code is pointed at the alias below.
  modelAlias = "qwen3-coder-30b";

  # Qwen Code speaks the OpenAI API, so it's configured through OPENAI_* env
  # vars. Those are deliberately baked into a wrapper instead of
  # environment.sessionVariables: setting OPENAI_BASE_URL session-wide would
  # silently redirect *every* tool that speaks the OpenAI API at this local
  # server. --set-default (not --set) so an explicit export still wins.
  #
  # All three of API key / model / base URL have to be set together: that exact
  # trio is what makes qwen-code infer `openai` as the auth type, which is what
  # lets this work with no settings.json at all. Set only two and it falls
  # through to the (now discontinued) Qwen OAuth path and fails. The key itself
  # is a placeholder — llama-server runs without --api-key and ignores it — but
  # it cannot be empty, or non-interactive `qwen -p '...'` refuses to start.
  #
  # The /v1 suffix is required; the base URL is handed to the OpenAI SDK
  # verbatim, with no normalization.
  #
  # ~/.qwen/settings.json is deliberately left alone, for the same reason
  # claude-code.nix leaves Claude's settings.json mutable — the CLI writes to it
  # at runtime and a read-only store symlink would make those writes fail. Note
  # that if you ever add a `modelProviders` entry there, its baseUrl *overrides*
  # OPENAI_BASE_URL rather than merging with it. Two knobs worth knowing if a
  # long agent turn misbehaves: generationConfig.timeout (defaults to 120s) and
  # maxRetries (defaults to 3, so a slow first token can triple-generate).
  # Brings the router up if it isn't already, then waits for it to answer. This
  # is what makes the service on-demand: `qwen` runs it before starting, and the
  # polkit rule below is what lets it do that without sudo. Also installed as a
  # standalone command so you can warm the server up by hand.
  #
  # It only waits for the *router* to respond, which is quick — it does not wait
  # for a model to load, since that's triggered by the first real request.
  llamaUp = pkgs.writeShellApplication {
    name = "llama-up";
    runtimeInputs = [
      pkgs.systemd
      pkgs.curl
    ];
    text = ''
      if ! systemctl is-active --quiet llama-cpp.service; then
        echo "llama-up: starting llama-cpp…" >&2
        systemctl start llama-cpp.service
      fi
      for _ in $(seq 1 60); do
        if curl -sf -o /dev/null "http://127.0.0.1:${toString port}/v1/models"; then
          exit 0
        fi
        sleep 0.5
      done
      echo "llama-up: server did not answer in 30s — journalctl -u llama-cpp" >&2
      exit 1
    '';
  };

  qwenLocal = pkgs.symlinkJoin {
    name = "qwen-code-local";
    paths = [ pkgs.qwen-code ];
    nativeBuildInputs = [ pkgs.makeWrapper ];
    postBuild = ''
      rm -f "$out/bin/qwen"
      makeWrapper ${pkgs.qwen-code}/bin/qwen "$out/bin/qwen" \
        --set-default OPENAI_BASE_URL "http://127.0.0.1:${toString port}/v1" \
        --set-default OPENAI_MODEL "${modelAlias}" \
        --set-default OPENAI_API_KEY "local-llama-cpp" \
        --run ${lib.escapeShellArg "${llamaUp}/bin/llama-up"}
    '';
  };
in

{
  services.llama-cpp = {
    enable = true;
    package = llamaCppVulkan;

    # Localhost only, so openFirewall stays off (its default). Router mode is
    # flagged experimental upstream and does no auth by default — don't bind
    # this to 0.0.0.0 without also setting --api-key.
    host = "127.0.0.1";
    inherit port;

    # Declaring modelsPreset (rather than `model`) is what puts the server in
    # router mode: nothing is loaded until a request names this model, and
    # weights are fetched from Hugging Face into LLAMA_CACHE
    # (/var/cache/llama-cpp, created by the unit's CacheDirectory) on first use.
    # That first request pays a ~16.5 GB download — `systemctl status llama-cpp`
    # or `journalctl -fu llama-cpp` to watch it.
    #
    # Keys are llama-server long flags minus the leading `--`, values are
    # strings because the module renders this straight to INI.
    modelsPreset."Qwen3-Coder-30B-A3B" = {
      # Qwen3-Coder-30B-A3B-Instruct — a 30B MoE with only 3B active params.
      # NB this is *not* Qwen3-Coder-Next, which despite the similar name is an
      # 80B MoE that would not fit in 32 GB without spilling experts to RAM.
      #
      # UD-Q4_K_XL (16.5 GB) is Unsloth's recommendation for a ~32 GB card.
      # UD-Q5_K_XL (20.2 GB) also fits alongside the cache below if you want
      # more fidelity; UD-Q6_K_XL (24.5 GB) does not at this context length.
      hf-repo = "unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF";
      hf-file = "Qwen3-Coder-30B-A3B-Instruct-UD-Q4_K_XL.gguf";
      alias = modelAlias;

      # Full offload — the whole model lives on the GPU. 99 rather than a real
      # layer count is the idiomatic "all of them".
      n-gpu-layers = "99";

      # 128K context. This number is not free choice — qwen-code assumes
      # DEFAULT_TOKEN_LIMIT = 131072 for any model name it doesn't recognize and
      # never asks the server how much context it actually has, so a smaller
      # value here would let it silently overflow the window mid-session.
      #
      # The KV cache, not the weights, is what makes that expensive: 48 layers x
      # 4 KV heads x 128 dim comes to ~96 KiB/token at f16, so 128K would want
      # ~12 GiB. Quantizing the cache to q8_0 roughly halves it to ~6.5 GiB,
      # which puts the total at ~23 GB of the 32 GB available. Quantized V
      # requires flash attention, hence -fa on; verified working on RADV.
      ctx-size = "131072";
      cache-type-k = "q8_0";
      cache-type-v = "q8_0";
      flash-attn = "on";

      # Qwen ships a chat template with tool-call support; the agent loop in
      # `qwen` depends on it, so jinja is not optional here.
      jinja = "on";

      # Qwen's published sampling recommendations for this model. It's a
      # non-thinking model — it emits no <think> blocks.
      temp = "0.7";
      top-p = "0.8";
      top-k = "20";
      min-p = "0.0";
      repeat-penalty = "1.05";
    };

    # Global flags; the router merges these into each preset it spawns.
    extraFlags = [
      # Release the GPU after 15 min idle, so a forgotten `qwen` session isn't
      # holding ~23 GB of VRAM when a game starts. The next request reloads from
      # the local cache. `systemctl stop llama-cpp` to free it immediately.
      "--sleep-idle-seconds"
      "900"
    ];
  };

  # Don't start at boot. The nixpkgs module hardcodes
  # wantedBy = [ "multi-user.target" ], so this has to be mkForce'd rather than
  # just set — an empty list would otherwise merge with the module's and lose.
  # The unit still exists and is startable; nothing pulls it in automatically.
  systemd.services.llama-cpp.wantedBy = lib.mkForce [ ];

  # Let jakek start/stop this one unit without sudo, so `llama-up` (and hence
  # `qwen`) works from a normal shell. Scoped to llama-cpp.service specifically
  # — this is not blanket systemd access.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (action.id == "org.freedesktop.systemd1.manage-units" &&
          action.lookup("unit") == "llama-cpp.service" &&
          subject.user == "jakek") {
        return polkit.Result.YES;
      }
    });
  '';

  environment.systemPackages = [
    llamaCppVulkan # llama-cli / llama-server / llama-bench, Vulkan-enabled
    qwenLocal # `qwen`, starts the server on demand then connects
    llamaUp # `llama-up` — start the server + wait, without running qwen
    pkgs.vulkan-tools # `vulkaninfo --summary` — confirms the GPU is a Vulkan device
  ];
}
