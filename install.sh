#!/usr/bin/zsh

autoload -U colors
colors

export COLUMNS=1
export services=(
  cups
  dhcpcd
  NetworkManager
  bluetooth
)

export user_services=(
  pipewire-media-session
  pipewire-pulse
  pipewire
)

select_boot() {
  select boot_part in $(lsblk -rnpo NAME | grep -E "/dev/(sd|nvme|vd)"); do
    echo "Selected boot_part: $fg[green]$boot_part$reset_color"
    break
  done
  [ ! -f $boot_part ] || select_boot
}

select_swap() {
  select swap_part in $(lsblk -rnpo NAME | grep -E "/dev/(sd|nvme|vd)"); do
    echo "Selected swap_part: $fg[green]$swap_part$reset_color"
    break
  done
  [ ! -f $swap_part ] || swap_part
}

select_root() {
  select root_part in $(lsblk -rnpo NAME | grep -E "/dev/(sd|nvme|vd)"); do
    echo "Selected root_part: $fg[green]$root_part$reset_color"
    break
  done
  [ ! -f $root_part ] || root_part
}

select_home() {
  select home_part in $(lsblk -rnpo NAME | grep -E "/dev/(sd|nvme|vd)"); do
    echo "Selected home_part: $fg[green]$home_part$reset_color"
    break
  done
  [ ! -f $home_part ] || home_part
}

# prompt to ask if they have partitioned
echo "$bold_color$fg[cyan]Do you have partitions on your disk?$reset_color"
select yn in "$fg[green]Yes$reset_color" "$fg[red]No$reset_color"; do
  case $yn in
    "$fg[green]Yes$reset_color" ) break;;
    "$fg[red]No$reset_color" ) echo "Please partition before running this script."; exit;;
  esac
done

echo -e "\n\n$bold_color$fg[cyan]Select the boot partition:$reset_color"
select_boot

echo -e "\n\n$bold_color$fg[cyan]Select the swap partition:$reset_color"
select_swap

echo -e "\n\n$bold_color$fg[cyan]Select the root partition:$reset_color"
select_root

echo -e "\n\n$bold_color$fg[cyan]Select the home partition:$reset_color"
select_home

echo -e "\n\n$bold_color$fg[cyan]Please check if the following is correct:$reset_color"
echo "Boot: $boot_part"
echo "Swap: $swap_part"
echo "Root: $root_part"
echo "Home: $home_part"

echo ""
select yn in "$fg[green]Yes$reset_color" "$fg[red]No$reset_color"; do
  case $yn in
    "$fg[green]Yes$reset_color" ) break;;
    "$fg[red]No$reset_color" ) echo "Please run this script again."; exit;;
  esac
done

# ask if they want to format boot
echo -e "\n\n$bold_color$fg[cyan]Do you want to format boot_part:$boot_part?$reset_color"
select yn in "$fg[green]Yes$reset_color" "$fg[red]No$reset_color"; do
  case $yn in
    "$fg[green]Yes$reset_color" ) mkfs.fat -F 32 $boot_part; break;;
    "$fg[red]No$reset_color" ) echo "Skipping formatting $boot_part"; break;;
  esac
done

# ask if they want to format home
echo -e "\n\n$bold_color$fg[cyan]Do you want to format home_part:$home_part?$reset_color"
select yn in "$fg[green]Yes$reset_color" "$fg[red]No$reset_color"; do
  case $yn in
    "$fg[green]Yes$reset_color" ) mkfs.btrfs -f $home_part; break;;
    "$fg[red]No$reset_color" ) echo "Skipping formatting home_part:$home_part"; break;;
  esac
done

# format root partition (mkfs.btrfs)
echo -e "\n\n$bold_color$fg[cyan]Formatting root_part:$root_part...$reset_color"
mkfs.btrfs -f $root_part

# format swap partition (mkswap)
echo -e "\n\n$bold_color$fg[cyan]Formatting swap_part:$swap_part...$reset_color"
mkswap $swap_part

# mount swap (swapon)
echo -e "\n\n$bold_color$fg[cyan]Mounting swap_part:$swap_part...$reset_color"
swapon $swap_part

# mount root partition
echo -e "\n\n$bold_color$fg[cyan]Mounting root_part:$root_part...$reset_color"
mount $root_part /mnt
mkdir /mnt/home
mkdir /mnt/boot

# mount home partition
echo -e "\n\n$bold_color$fg[cyan]Mounting home_part:$home_part...$reset_color"
mount $home_part /mnt/home

# mount boot partition
echo -e "\n\n$bold_color$fg[cyan]Mounting boot_part:$boot_part...$reset_color"
mount $boot_part /mnt/boot

# enable ParallelDownloads to 16
sed -i 's/#ParallelDownloads.*/ParallelDownloads = 15/g' /etc/pacman.conf

# pacstrap
echo -e "\n\n$bold_color$fg[cyan]Installing base packages...$reset_color"
pacstrap /mnt base base-devel linux-zen linux-zen-headers linux-firmware nano btrfs-progs intel-ucode refind efibootmgr reflector dhcpcd networkmanager git zsh bluez bluez-utils

# prompts for hostname and password
echo -e "\n\n$bold_color$fg[cyan]Enter a hostname:$reset_color "
read hostname
echo $hostname > /mnt/etc/hostname

echo -e "\n\n$bold_color$fg[cyan]Enter your password:$reset_color "
read -s password

# generate fstab
echo -e "\n\n$bold_color$fg[cyan]Generating fstab...$reset_color"
genfstab -U /mnt >> /mnt/etc/fstab

# locales
echo "en_US.UTF-8 UTF-8"  > /mnt/etc/locale.gen
echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf

# /etc/hosts gen
echo -e "\n\n$bold_color$fg[cyan]Generating /etc/hosts...$reset_color"
cat << EOF > /etc/hosts
# Static table lookup for hostnames.
# See hosts(5) for details.
127.0.0.1   localhostw
::1         localhost
127.0.1.1   $hostname.localdomain   $hostname
EOF

# create default user
echo -e "\n\n$bold_color$fg[cyan]Enter your username:$reset_color "
read default_user

echo -e "\n\n$bold_color$fg[cyan]Creating user...$reset_color "
arch-chroot /mnt useradd -m -G wheel -s /usr/bin/zsh "$default_user"
sed -i 's/# %wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) NOPASSWD: ALL/' /mnt/etc/sudoers

# set passwords
echo -e "\n\n$bold_color$fg[cyan]Setting root password...$reset_color"
echo "root:$password" | arch-chroot /mnt chpasswd
echo -e "\n\n$bold_color$fg[cyan]Setting $default_user password...$reset_color"
echo "$default_user:$password" | arch-chroot /mnt chpasswd

# perf stuff
echo -e "\n\n$bold_color$fg[cyan]Tuning initramfs hooks to performance...$reset_color"
cat << EOF > /etc/mkinitcpio.conf
MODULES=()
BINARIES=()
FILES=()
HOOKS=(base udev autodetect modconf block filesystems keyboard fsck resume)
EOF

echo -e "\n\n$bold_color$fg[cyan]Regenerating initramfs...$reset_color"
arch-chroot /mnt mkinitcpio -P

sed -i 's/#ParallelDownloads.*/ParallelDownloads = 15/g' /mnt/etc/pacman.conf
arch-chroot /mnt /bin/bash -e <<EOF
  # set timezone
  echo -e "\n\n$bold_color$fg[cyan]Setting timezone...$reset_color"
  ln -sf /usr/share/zoneinfo/America/Los_Angeles /etc/localtime &>/dev/null

  # set system clock
  echo -e "\n\n$bold_color$fg[cyan]Setting system clock...$reset_color"
  hwclock --systohc

  # gen locales
  echo -e "\n\n$bold_color$fg[cyan]Generating locales...$reset_color"
  locale-gen &>/dev/null

  # install refind
  echo -e "\n\n$bold_color$fg[cyan]Installing refind...$reset_color"
  refind-install &>/dev/null

  # install chaotic-aur
  echo -e "\n\n$bold_color$fg[cyan]Installing chaotic-aur...$reset_color"
  pacman-key --recv-key FBA220DFC880C036 --keyserver keyserver.ubuntu.com
  pacman-key --lsign-key FBA220DFC880C036
  pacman --noconfirm -U 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst' 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'
  echo -e "[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist" >> /etc/pacman.conf

  # login to diced
  sudo su diced -s /bin/bash
  whoami
  cd ~

  # install paru-bin
  rm -rf paru-bin
  echo -e "\n\n$bold_color$fg[cyan]Installing paru-bin...$reset_color"
  git clone https://aur.archlinux.org/paru-bin.git
  cd paru-bin
  makepkg -si --noconfirm
  cd ..
  rm -rf paru-bin

  # install essential packages
  echo -e "\n\n$bold_color$fg[cyan]Installing essential packages...$reset_color"
  paru --noconfirm -Syy cups bc ttf-font-awesome xorg-xinit xcolor xfce4-notifyd xfce4-volumed-pulse lxappearance antibody-bin bluez bluez-utils pavucontrol pipewire-pulse pipewire-media-session playerctl brightnessctl ttf-twemoji ttf-ms-fonts shotcut lightdm gnome-keyring neofetch aur/gotop htop xorg xdotool obs-studio brave-bin bspwm sxhkd chaotic-aur/polybar aur/ulauncher visual-studio-code-insiders-bin alacritty papirus-icon-theme feh picom flameshot xcursor-simp1e-dark aur/spotify firefox-developer-edition nautilus ttf-jetbrains-mono nerd-fonts-jetbrains-mono ttf-ubuntu-font-family matcha-gtk-theme-git

  # clone my dotfiles
  cd ~
  echo -e "\n\n$bold_color$fg[cyan]Cloning dotfiles...$reset_color"
  git clone --bare https://github.com/diced/dotfiles.git /home/$default_user/.cfg
  git --git-dir=/home/$default_user/.cfg/ --work-tree=/home/$default_user checkout

  sudo systemctl enable cups
  sudo systemctl enable NetworkManager
  sudo systemctl enable dhcpcd
  sudo systemctl enable bluetooth
EOF

# standard options with perf params5
echo -e "\n\n$bold_color$fg[cyan]Generating refind menu (with perf params)...$reset_color"
cat << EOF > /mnt/boot/refind_linux.conf
"Boot with standard options"  "rw root=$root_part initrd=intel-ucode.img initrd=initramfs-linux-zen.img quiet loglevel=3 rd.systemd.show_status=auto rd.udev.log_level=3 nowatchdog acpi_mask_gpe=0x6E"
"Boot with minimal options"   "ro root=$root_part initrd=intel-ucode.img initrd=initramfs-linux-zen.img"
EOF

echo -e "\n\n$bold_color$fg[green]Finished install! Reboot for changes to take effect.$reset_color"

umount -R /mnt