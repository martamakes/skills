# Guía de Branding - SantiComet

## Paleta de Colores Primaria
Paleta cósmica inspirada en cometas y energía espacial, vibrante pero sofisticada:

| Color | Hex | Uso |
|-------|-----|-----|
| **Comet Core** | `#1e4876` | Fondo hero, botones primarios |
| **Nebula Blue** | `#4b789b` | Hover states, secundarios |
| **Star Dust** | `#8ba4b1` | Textos secundarios, borders |
| **Solar Flare** | `#f1c84b` | Accent, highlights, CTAs |
| **Meteor Burn** | `#d65b2e` | Alertas, iconos energía  [colormagic](https://colormagic.app/es/palette/67126aaceab8122db20f7cae) |

**Variables CSS:**
```css
:root {
  --comet-core: #1e4876;
  --nebula-blue: #4b789b;
  --star-dust: #8ba4b1;
  --solar-flare: #f1c84b;
  --meteor-burn: #d65b2e;
}
```

## Tipografía
```
Primary: "Inter" o "SF Pro" (sans-serif moderna)
Secondary: "Space Grotesk" (títulos grandes)
Fallback: -apple-system, BlinkMacSystemFont, sans-serif
```

- **H1**: 64px bold / 48px mobile
- **H2**: 40px bold / 32px mobile  
- **Body**: 16px regular / 18px mobile
- **Small**: 14px

## Estilo Web (Inspirado en Billie Eilish + Tame Impala)

### Hero Section
```
🌌 Fondo: Gradiente radial (#1e4876 → #000814) + partículas animadas
🎸 Foto oversized Santi (70% viewport) con overlay --comet-core 0.7
✨ Título animado: "SANTI COMET" con glitch effect (--solar-flare glow)
🎵 Waveform animada sutil de su última canción
🔥 CTA oversized: "NUEVO SINGLE" (--solar-flare + --meteor-burn hover)
```

### Navegación
```
🌓 Dark mode only: --comet-core + --star-dust
📱 Fixed left sidebar (300px) con scroll suave
🎚️ Scroll indicator cósmico (--solar-flare)
```

### Sección Discografía
```
💿 Grid cards con hover 3D transform
🎨 Portadas con border-radius 24px + --solar-flare glow
⏱️ Player inline Spotify/YouTube (90% width)
⭐ Rating animado con estrellas --solar-flare
```

### Sección Live
```
🗓️ Calendar con eventos animados (--meteor-burn pulse)
🎫 Tickets con countdown timer
📍 Mapa interactivo con geolocalización
```

### Footer
```
🌙 Gradiente inverso (--comet-core → #000814)
🔗 Redes sociales con iconos animados
📧 Newsletter signup (--solar-flare CTA)
© 2026 SantiComet - All Rights Reserved
```

## Animaciones Clave
- **Page load**: Fade-in staggered 0.2s
- **Hover cards**: Scale 1.05 + shadow --solar-flare glow
- **CTA**: Pulse infinito 2s (--meteor-burn)
- **Scroll**: Parallax sutil (20px) en hero image
- **Navbar**: Slide-in from left 0.4s

## Responsive Breakpoints
```
XL: 1440px+ → 4-column grid
LG: 1024px → 3-column  
MD: 768px → 2-column  
SM: 480px → 1-column
```

## Moodboard Referencias
- **Billie Eilish**: Dark minimalismo + tipografía oversized
- **Tame Impala**: Gradientes psicodélicos + animaciones fluidas  
- **The Weeknd**: Hero sections inmersivas + video backgrounds
- **Harry Styles**: Grid cards elegantes + hover effects

**Personalidad SantiComet**: Moderno, enérgico, cósmico, accesible pero premium. La web debe sentirse como un cometa: rápida, brillante, imposible de ignorar.

***

