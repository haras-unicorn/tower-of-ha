def --wrapped "main rebuild switch" [
  ...args: string
] {
  (sudo nixos-rebuild switch
    --flake $"(toh flake)#(hostname)"
    ...($args))
}

def --wrapped "main rebuild boot" [
  ...args: string
] {
  (sudo nixos-rebuild boot
    --flake $"(toh flake)#(hostname)"
    ...($args))
}

