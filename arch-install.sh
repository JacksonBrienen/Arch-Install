#!/bin/bash

# Capture details before starting the automated process
read -p "Enter hostname: " myhostname
read -p "Enter username: " myusername
read -sp "Enter password for $myusername: " mypassword
echo ""

# Sync Clock
timedatectl set-ntp true

# GPT Partitioning - 512MB Boot, 4GB Swap, Rest as Root
parted /dev/nvme0n1 mklabel gpt
parted /dev/nvme0n1 mkpart "EFI" fat32 1MiB 513MiB
parted /dev/nvme0n1 set 1 esp on
parted /dev/nvme0n1 mkpart "swap" linux-swap 513MiB 4609MiB
parted /dev/nvme0n1 mkpart "root" ext4 4609MiB 100%

# Format Partitions
mkfs.fat -F 32 /dev/nvme0n1p1
mkswap /dev/nvme0n1p2
swapon /dev/nvme0n1p2
mkfs.ext4 /dev/nvme0n1p3

mount /dev/nvme0n1p3 /mnt
mount --mkdir /dev/nvme0n1p1 /mnt/boot

# Base Install - Intel Specific Chipset and Video drivers
pacstrap -K /mnt base base-devel linux linux-firmware intel-ucode mesa vulkan-intel intel-media-driver sudo git vim networkmanager hyprland xdg-desktop-portal-hyprland waybar hyprpaper wofi qt5-wayland qt6-wayland sddm

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# Enter Installation
arch-chroot /mnt /bin/bash <<'EOF'
# Re-import variables into the chroot environment
export myhostname=$(cat /etc/hostname)
# We need to pass the username and password explicitly since 'EOF' is quoted
EOF

# Timezone, locale, and other environment variables
cat <<SYSTEM_CONFIG > /mnt/setup.sh
#!/bin/bash
ln -sf /usr/share/zoneinfo/America/Los_Angeles /etc/localtime
hwclock --systohc
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "LIBVA_DRIVER_NAME=iHD" >> /etc/environment
echo "XDG_SESSION_TYPE=wayland" >> /etc/environment
echo "$myhostname" > /etc/hostname
systemctl enable NetworkManager
systemctl enable sddm

# User Management
useradd -m -G wheel "$myusername"
echo "$myusername:$mypassword" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
passwd -l root

# Yay & Ghostty
sudo -u "$myusername" bash <<'AUR'
cd /home/$(whoami)
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm
cd ..
rm -rf yay
yay -S --noconfirm ghostty
mkdir -p ~/.config/hypr
echo "\$terminal = ghostty
bind = SUPER, Q, exec, \$terminal
bind = SUPER, M, exit,
bind = SUPER, R, exec, wofi --show drun" > ~/.config/hypr/hyprland.conf
AUR

# Bootloader
bootctl install
PARTUUID=\$(blkid -s PARTUUID -o value /dev/nvme0n1p3)
echo "title   Arch Linux
linux   /vmlinuz-linux
initrd  /intel-ucode.img
initrd  /initramfs-linux.img
options root=PARTUUID=\$PARTUUID rw" > /boot/loader/entries/arch.conf
echo "default arch.conf
timeout 3
console-mode max" > /boot/loader/loader.conf
SYSTEM_CONFIG

# Execute the setup script inside chroot
arch-chroot /mnt /bin/bash /setup.sh
rm /mnt/setup.sh

echo "Installation complete! Unmount and reboot."
