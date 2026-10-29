# Dashy

This directory contains the Dashy Compose template, the optional WUD overlay, and a generic starting configuration at **conf.yml.example**. It uses the shared homelab look and layout with placeholder host, network, and service values.

## Shared dashboard baseline

The example is intended to keep the same behavior on phones, tablets, and desktop screens:

- Open Dashy's default Home view, use the Glass theme, horizontal section layout, and large items.
- Disable configuration editing and hide search and settings controls.
- Keep navigation links visible, centered at the top, and sticky while scrolling. Give links consistent gaps and let them wrap on narrow screens.
- Center the title and description below the navigation, with a small gap; the title scrolls with the page instead of staying sticky.
- Hide section open, options, and expand/collapse controls, and prevent section headers from toggling sections.
- Open service cards in a new browser tab by default. Individual cards can override this with their own `target` value.
- Keep the footer visible and sticky. Its two centered rows wrap as needed and are separated by a divider. Footer links inherit the theme color and are underlined.

The app behavior is set under `appConfig`; custom CSS handles the navigation, section controls, and sticky footer layout. The footer's HTML lives under `pageInfo.footer`. The CSS selectors follow Dashy's current page structure, so visually check the result when changing Dashy versions.

## Use the example

From the infra-docker-templates repository root, copy **conf.yml.example** to **conf.yml** in the host directory mounted by Compose. With the default Compose variables, that path is **/tmp/dashy/conf.yml**:

    mkdir -p /tmp/dashy
    cp dashy/conf.yml.example /tmp/dashy/conf.yml

If you set **VOLUMES_BASE** or **CONTAINER_NAME**, use the corresponding **VOLUMES_BASE/CONTAINER_NAME/conf.yml** path instead.

Before starting Dashy:

- Replace the title, description, navigation links, VLAN, local address, and footer links.
- Search is hidden in this baseline. If you enable it later, configure its search engine under `appConfig`.
- Replace the example service cards and URLs, then remove unused sections.
- Keep each section populated with at least one item or widget.
- Replace the logo URL if you want to use a different image.

The example disables configuration editing with `disableConfiguration: true`. Edit **conf.yml** on the host to make changes.

Restart or refresh Dashy after saving the file.

The Compose template mounts only **conf.yml**. If you add Dashy sub-pages or local assets, mount those files under **/app/user-data** as well. Dashy documents the config format and Docker user-data directory in its [configuration reference](https://dashy.to/docs/configuring/) and [Docker quick start](https://github.com/lissy93/dashy/blob/master/docs/quick-start.md).
