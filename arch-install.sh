#!/bin/bash

# --- 1. User Input ---
read -p "Enter hostname: " myhostname
read -p "Enter username: " myusername
read -sp "Enter password for $myusername: " mypassword
echo ""

# --- 2. System Prep ---
timedatectl set-ntp true

# Partitioning /dev/nvme0n1 (GPT, 512MB Boot, 4GB Swap, Rest Root)
parted /dev/nvme0n1 mklabel gpt
parted /dev/nvme0n1 mkpart "EFI" fat32 1MiB 513MiB
parted /dev/nvme0n1 set 1 esp on
parted /dev/nvme0n1 mkpart "swap" linux-swap 513MiB 4609MiB
parted /dev/nvme0n1 mkpart "root" ext4 4609MiB 100%

# Formatting
mkfs.fat -F 32 /dev/nvme0n1p1
mkswap /dev/nvme0n1p2
swapon /dev/nvme0n1p2
mkfs.ext4 /dev/nvme0n1p3

# Mounting
mount /dev/nvme0n1p3 /mnt
mount --mkdir /dev/nvme0n1p1 /mnt/boot

# --- 3. Base Installation ---
# Core + Intel 12th Gen Video + Hyprland + Bluetooth + Network Applets
pacstrap -K /mnt base base-devel linux linux-firmware intel-ucode mesa vulkan-intel \
intel-media-driver sudo git vim networkmanager network-manager-applet \
hyprland xdg-desktop-portal-hyprland waybar hyprpaper wofi qt5-wayland qt6-wayland \
sddm bluez bluez-utils blueman

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# --- 4. Internal Setup Script ---
cat <<INTERNAL_CONFIG > /mnt/setup.sh
#!/bin/bash

# System Clock & Locale
ln -sf /usr/share/zoneinfo/America/Los_Angeles /etc/localtime
hwclock --systohc
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Intel Media & Wayland variables
echo "LIBVA_DRIVER_NAME=iHD" >> /etc/environment
echo "XDG_SESSION_TYPE=wayland" >> /etc/environment

# Enable Services
echo "$myhostname" > /etc/hostname
systemctl enable NetworkManager
systemctl enable sddm
systemctl enable bluetooth

# User & Sudo Setup
useradd -m -G wheel "$myusername"
echo "$myusername:$mypassword" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
passwd -l root

# Install Yay & Ghostty as User
sudo -u "$myusername" bash <<'AUR'
export HOME=/home/"$myusername"
cd /home/"$myusername"

git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm
cd ..
rm -rf yay

yay -S --noconfirm ghostty

# Pre-configure Hyprland
mkdir -p ~/.config/hypr
echo "\\\$terminal = ghostty
# Execute applets in background
exec-once = nm-applet --indicator
exec-once = blueman-applet
exec-once = waybar

# Keybinds
bind = SUPER, Q, exec, \\\$terminal
bind = SUPER, M, exit,
bind = SUPER, R, exec, wofi --show drun
bind = SUPER, C, killactive," > ~/.config/hypr/hyprland.conf
AUR

# Final Permissions Fix
chown -R "$myusername":"$myusername" /home/"$myusername"

# Bootloader setup (systemd-boot)
bootctl install
UUID=\$(blkid -s PARTUUID -o value /dev/nvme0n1p3)
echo "title   Arch Linux
linux   /vmlinuz-linux
initrd  /intel-ucode.img
initrd  /initramfs-linux.img
options root=PARTUUID=\$UUID rw" > /boot/loader/entries/arch.conf

echo "default arch.conf
timeout 3
console-mode max" > /boot/loader/loader.conf
INTERNAL_CONFIG

# --- 5. Execution ---
chmod +x /mnt/setup.sh
arch-chroot /mnt /bin/bash /setup.sh
rm /mnt/setup.sh

echo "--------------------------------------------------"
echo "Setup Complete! Type: umount -R /mnt && reboot"
