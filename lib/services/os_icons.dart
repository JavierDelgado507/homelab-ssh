import 'package:flutter/widgets.dart';
import 'package:simple_icons/simple_icons.dart';

/// Logo del sistema operativo detectado al conectar (ID de /etc/os-release,
/// 'proxmox' si existe /etc/pve, o el uname en minúsculas como último recurso).
IconData? osIcon(String? id) {
  switch (id) {
    case 'proxmox':
      return SimpleIcons.proxmox;
    case 'debian':
      return SimpleIcons.debian;
    case 'ubuntu':
      return SimpleIcons.ubuntu;
    case 'fedora':
      return SimpleIcons.fedora;
    case 'arch':
    case 'archlinux':
      return SimpleIcons.archlinux;
    case 'alpine':
      return SimpleIcons.alpinelinux;
    case 'centos':
      return SimpleIcons.centos;
    case 'rhel':
    case 'redhat':
      return SimpleIcons.redhat;
    case 'opensuse':
    case 'opensuse-leap':
    case 'opensuse-tumbleweed':
      return SimpleIcons.opensuse;
    case 'raspbian':
      return SimpleIcons.raspberrypi;
    case 'freebsd':
      return SimpleIcons.freebsd;
    case 'darwin':
    case 'macos':
      return SimpleIcons.apple;
    case null:
      return null;
    default:
      // Distro sin logo propio en la fuente: pingüino genérico
      return SimpleIcons.linux;
  }
}
