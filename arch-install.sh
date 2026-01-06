#!/bin/bash

# --- 1. User Input ---
read -p "Enter hostname: " myhostname
read -p "Enter username: " myusername
read -sp "Enter password for $myusername: " mypassword
echo ""

# --- 2. System Prep ---
timedatectl set-ntp true

# Partitioning /dev/nvme0n1
# 1MiB offset for SSD alignment
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
# Includes base-devel for AUR, Intel drivers for 12th gen, and Hyprland stack
pacstrap -K /mnt base base-devel linux linux-firmware intel-ucode mesa vulkan-intel intel-media-driver sudo git vim networkmanager hyprland xdg-desktop-portal-hyprland waybar hyprpaper wofi qt5-wayland qt6-wayland sddm

# Generate fstab
genfstab -U /mnt >> /mnt/etc/fstab

# --- 4. Creating the Internal Setup Script ---
# Using a temp script solves the permission and variable bugs
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

# Networking & Login Manager
echo "$myhostname" > /etc/hostname
systemctl enable NetworkManager
systemctl enable sddm

# User & Sudo Setup
useradd -m -G wheel "$myusername"
echo "$myusername:$mypassword" | chpasswd
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
passwd -l root

# Install Yay & Ghostty as the standard user
# Setting HOME is critical for makepkg to work in chroot
sudo -u "$myusername" bash <<AUR
export HOME=/home/"$myusername"
cd /home/"$myusername"

git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm
cd ..
rm -rf yay

# Install Ghostty from AUR
yay -S --noconfirm ghostty

# Pre-configure Hyprland to use Ghostty
mkdir -p ~/.config/hypr
echo "\\\$terminal = ghostty
bind = SUPER, Q, exec, \\\$terminal
bind = SUPER, M, exit,
bind = SUPER, R, exec, wofi --show drun" > ~/.config/hypr/hyprland.conf

AUR

# Fix permissions one last time
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
echo "Setup Complete! You can now type:"
echo "umount -R /mnt"
echo "reboot"
