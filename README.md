# ErnBurglary
OpenMW mod that adds Spell Books, which teach you a spell when you cast them. Rare Corrupted Spell Books have additional wild effects! Spell Books are a pathway to many abilities the Mages Guild consider to be unnatural.

Spell Books can contain a huge variety of spells, since they are drawn from all existing (suitable) spells in your world, including those added from other mods.

Spell Books can spawn on magic-using NPCs or in appropriate containers. A few will also be for sale in any book shop, which will be restocked once per day.

![a wizard with a spellbook, created with AI](title_image.jpg)

## Installing
Extract [main](https://github.com/erinpentecost/ErnBurglary/archive/refs/heads/main.zip) to your `mods/` folder.


In your `openmw.cfg` file, and add these lines in the correct spots:

```yaml
data="/wherevermymodsare/mods/ErnBurglary-main"
content=ErnBurglary.omwaddon
content=ErnBurglary.omwscripts
```

## Contributing

Feel free to submit a PR to the [repo](https://github.com/erinpentecost/ErnBurglary) provided you certify your contribution under the [Developer Certificate of Origin](https://developercertificate.org/).

### omwaddon
The omwaddon contains these entries:
* enchantment: `ErnBurglary_LearnEnchantment` (casts DrainMagicka on self for 1 sec)
* spell: `ErnBurglary_restore_magicka`. effects are duration = 2^(index of effect - 1)

### TODO
* Corruption Orbs
* More Corruptions