#include "spellutil.hpp"

#include <limits>

#include "../mwbase/environment.hpp"
#include "../mwbase/windowmanager.hpp"
#include "../mwbase/world.hpp"

#include "../mwworld/class.hpp"
#include "../mwworld/esmstore.hpp"

#include "actorutil.hpp"
#include "creaturestats.hpp"
#include <components/settings/settings.hpp>

namespace MWMechanics
{
    ESM::Skill::SkillEnum spellSchoolToSkill(int school)
    {
        static const std::array<ESM::Skill::SkillEnum, 6> schoolSkillArray
        {
            ESM::Skill::Alteration, ESM::Skill::Conjuration, ESM::Skill::Destruction,
            ESM::Skill::Illusion, ESM::Skill::Mysticism, ESM::Skill::Restoration
        };
        return schoolSkillArray.at(school);
    }

    float calcEffectCost(const ESM::ENAMstruct& effect, const ESM::MagicEffect* magicEffect)
    {
        const MWWorld::ESMStore& store = MWBase::Environment::get().getWorld()->getStore();
        if (!magicEffect)
            magicEffect = store.get<ESM::MagicEffect>().find(effect.mEffectID);
        bool hasMagnitude = !(magicEffect->mData.mFlags & ESM::MagicEffect::NoMagnitude);
        bool hasDuration = !(magicEffect->mData.mFlags & ESM::MagicEffect::NoDuration);
        bool appliedOnce = magicEffect->mData.mFlags & ESM::MagicEffect::AppliedOnce;
        int minMagn = hasMagnitude ? effect.mMagnMin : 1;
        int maxMagn = hasMagnitude ? effect.mMagnMax : 1;
        int duration = hasDuration ? effect.mDuration : 1;
        if (!appliedOnce)
            duration = std::max(1, duration);
        static const float fEffectCostMult = store.get<ESM::GameSetting>().find("fEffectCostMult")->mValue.getFloat();

        float x = 0.5 * (std::max(1, minMagn) + std::max(1, maxMagn));
        x *= 0.1 * magicEffect->mData.mBaseCost;
        x *= 1 + duration;
        x += 0.05 * std::max(1, effect.mArea) * magicEffect->mData.mBaseCost;

        return x * fEffectCostMult;
    }

    int getEffectiveEnchantmentCastCost(float castCost, const MWWorld::Ptr &actor)
    {
        /*
         * Each point of enchant skill above/under 10 subtracts/adds
         * one percent of enchantment cost while minimum is 1.
         */
        int eSkill = actor.getClass().getSkill(actor, ESM::Skill::Enchant);
        const float result = castCost - (castCost / 100) * (eSkill - 10);

        return static_cast<int>((result < 1) ? 1 : result);
    }

    float calcSpellBaseSuccessChance (const ESM::Spell* spell, const MWWorld::Ptr& actor, int* effectiveSchool)
    {
        // Morrowind for some reason uses a formula slightly different from magicka cost calculation
        float y = std::numeric_limits<float>::max();
        float lowestSkill = 0;

        for (const ESM::ENAMstruct& effect : spell->mEffects.mList)
        {
            float x = static_cast<float>(effect.mDuration);
            const auto magicEffect = MWBase::Environment::get().getWorld()->getStore().get<ESM::MagicEffect>().find(effect.mEffectID);

            if (!(magicEffect->mData.mFlags & ESM::MagicEffect::AppliedOnce))
                x = std::max(1.f, x);

            x *= 0.1f * magicEffect->mData.mBaseCost;
            x *= 0.5f * (effect.mMagnMin + effect.mMagnMax);
            x += effect.mArea * 0.05f * magicEffect->mData.mBaseCost;
            if (effect.mRange == ESM::RT_Target)
                x *= 1.5f;
            static const float fEffectCostMult = MWBase::Environment::get().getWorld()->getStore().get<ESM::GameSetting>().find(
                        "fEffectCostMult")->mValue.getFloat();
            x *= fEffectCostMult;

            float s = 2.0f * actor.getClass().getSkill(actor, spellSchoolToSkill(magicEffect->mData.mSchool));
            if (s - x < y)
            {
                y = s - x;
                if (effectiveSchool)
                    *effectiveSchool = magicEffect->mData.mSchool;
                lowestSkill = s;
            }
        }

        CreatureStats& stats = actor.getClass().getCreatureStats(actor);

        float actorWillpower = stats.getAttribute(ESM::Attribute::Willpower).getModified();
        float actorLuck = stats.getAttribute(ESM::Attribute::Luck).getModified();

        float castChance = (lowestSkill - spell->mData.mCost + 0.2f * actorWillpower + 0.1f * actorLuck);

        return castChance;
    }

    float getSpellSuccessChance (const ESM::Spell* spell, const MWWorld::Ptr& actor, int* effectiveSchool, bool cap, bool checkMagicka)
    {
        // NB: Base chance is calculated here because the effective school pointer must be filled
        int effectiveSchoolVal;  // We may need the school for adjusting cast chance, even if a pointer wasn't passed in
        float baseChance = calcSpellBaseSuccessChance(spell, actor, &effectiveSchoolVal);
        if (effectiveSchool != nullptr)
        {
            *effectiveSchool = effectiveSchoolVal; // Update the pointer passed in if it isn't nullptr
        }

        bool godmode = actor == getPlayer() && MWBase::Environment::get().getWorld()->getGodModeState();

        CreatureStats& stats = actor.getClass().getCreatureStats(actor);

        if (stats.getMagicEffects().get(ESM::MagicEffect::Silence).getMagnitude() && !godmode)
            return 0;

        if (spell->mData.mType == ESM::Spell::ST_Power)
            return stats.getSpells().canUsePower(spell) ? 100 : 0;

        if (godmode)
            return 100;

        if (spell->mData.mType != ESM::Spell::ST_Spell)
            return 100;

        if (checkMagicka && spell->mData.mCost > 0 && stats.getMagicka().getCurrent() < spell->mData.mCost)
            return 0;

        if (spell->mData.mFlags & ESM::Spell::F_Always)
            return 100;

        float castBonus = -stats.getMagicEffects().get(ESM::MagicEffect::Sound).getMagnitude();
        float castChance = baseChance + castBonus;
        float fatigueTerm = stats.getFatigueTerm();
        castChance *= fatigueTerm;

        if (Settings::Manager::getBool("easy spells usually succeed", "Game"))
        {
            // Magicka cost will increase to simultaneously increase chance of success, up to the caster's available magicka.
            castChance *= getMagickaLimitedAdjustedSpellCost(*spell, actor, stats.getMagicka().getCurrent(), fatigueTerm, effectiveSchoolVal) / spell->mData.mCost;
        }

        return std::max(0.f, cap ? std::min(100.f, castChance) : castChance);
    }

    float getSpellSuccessChance (const std::string& spellId, const MWWorld::Ptr& actor, int* effectiveSchool, bool cap, bool checkMagicka)
    {
        if (const auto spell = MWBase::Environment::get().getWorld()->getStore().get<ESM::Spell>().search(spellId))
            return getSpellSuccessChance(spell, actor, effectiveSchool, cap, checkMagicka);
        return 0.f;
    }

    float getAdjustedSpellCost(const ESM::Spell& spell, const MWWorld::Ptr& actor, int spellSchool)
    {
        if (Settings::Manager::getBool("easy spells usually succeed", "Game"))
        {
            const CreatureStats& stats = actor.getClass().getCreatureStats(actor);
            float spellSkill = actor.getClass().getSkill(actor, MWMechanics::spellSchoolToSkill(spellSchool));
            float actorWillpower = stats.getAttribute(ESM::Attribute::Willpower).getModified();
            float actorLuck = stats.getAttribute(ESM::Attribute::Luck).getModified();

            // this is the point at which the spell will always succeed (barring "sound" spells) and magicka cost starts going down even more quickly
            float skillThreshold = spell.mData.mCost - 0.2f * actorWillpower - 0.1f * actorLuck;

            // below this skill level, chance to successfully cast is zero no matter what
            // everything is halved since skill is multiplied by 2 in the cast chance calculation
            float minSkill = 0.5f * skillThreshold;

            // Once the skill level passes the threshold at which the spell always succeeds, the cost starts going down more rapidly
            // This is effectively just the base cast chance once skill passes skill threshold (and just the skill level itself before that threshold)
            float adjustedSkill = std::max(minSkill, spellSkill + std::max(0.0f, spellSkill - skillThreshold));

            // Magicka cost will increase to simultaneously increase chance of success
            // Cost should never drop below base cost
            return spell.mData.mCost * std::max(1.0f, 100.0f / adjustedSkill);
        }
        else
        {
            return spell.mData.mCost;
        }
    }

    float getMagickaLimitedAdjustedSpellCost(const ESM::Spell& spell, const MWWorld::Ptr& actor, float magicka, float fatigueTerm, int spellSchool)
    {
        if (Settings::Manager::getBool("easy spells usually succeed", "Game"))
        {
            float baseCost = static_cast<float>(spell.mData.mCost);

            // Magicka cost is limited to the caster's available magicka, or the base cost of the spell, whichever is more.
            // Also, don't let fatigue term drop adjusted cost below base cost
            return std::min(std::max(baseCost, getAdjustedSpellCost(spell, actor, spellSchool) / fatigueTerm), std::max(baseCost, magicka));
        }
        else
        {
            return spell.mData.mCost;
        }
    }

    float getMagickaLimitedAdjustedSpellCost(const ESM::Spell& spell, const MWWorld::Ptr& actor, float magicka, float fatigueTerm)
    {
        if (Settings::Manager::getBool("easy spells usually succeed", "Game"))
        {
            return getMagickaLimitedAdjustedSpellCost(spell, actor, magicka, fatigueTerm, MWMechanics::getSpellSchool(&spell, actor));
        }
        else
        {
            return spell.mData.mCost;
        }
    }

    float getMagickaLimitedAdjustedSpellCost(const ESM::Spell& spell, const MWWorld::Ptr& actor, float magicka)
    {
        if (Settings::Manager::getBool("easy spells usually succeed", "Game"))
        {
            return getMagickaLimitedAdjustedSpellCost(spell, actor, magicka, actor.getClass().getCreatureStats(actor).getFatigueTerm());
        }
        else
        {
            return spell.mData.mCost;
        }
    }

    int getSpellSchool(const std::string& spellId, const MWWorld::Ptr& actor)
    {
        int school = 0;
        getSpellSuccessChance(spellId, actor, &school);
        return school;
    }

    int getSpellSchool(const ESM::Spell* spell, const MWWorld::Ptr& actor)
    {
        int school = 0;
        getSpellSuccessChance(spell, actor, &school);
        return school;
    }

    bool spellIncreasesSkill(const ESM::Spell *spell)
    {
        return spell->mData.mType == ESM::Spell::ST_Spell && !(spell->mData.mFlags & ESM::Spell::F_Always);
    }

    bool spellIncreasesSkill(const std::string &spellId)
    {
        const auto spell = MWBase::Environment::get().getWorld()->getStore().get<ESM::Spell>().search(spellId);
        return spell && spellIncreasesSkill(spell);
    }

    bool checkEffectTarget (int effectId, const MWWorld::Ptr& target, const MWWorld::Ptr& caster, bool castByPlayer)
    {
        switch (effectId)
        {
            case ESM::MagicEffect::Levitate:
            {
                if (!MWBase::Environment::get().getWorld()->isLevitationEnabled())
                {
                    if (castByPlayer)
                        MWBase::Environment::get().getWindowManager()->messageBox("#{sLevitateDisabled}");
                    return false;
                }
                break;
            }
            case ESM::MagicEffect::Soultrap:
            {
                if (!target.getClass().isNpc() // no messagebox for NPCs
                     && (target.getTypeName() == typeid(ESM::Creature).name() && target.get<ESM::Creature>()->mBase->mData.mSoul == 0))
                {
                    if (castByPlayer)
                        MWBase::Environment::get().getWindowManager()->messageBox("#{sMagicInvalidTarget}");
                    return true; // must still apply to get visual effect and have target regard it as attack
                }
                break;
            }
            case ESM::MagicEffect::WaterWalking:
            {
                if (target.getClass().isPureWaterCreature(target) && MWBase::Environment::get().getWorld()->isSwimming(target))
                    return false;

                MWBase::World *world = MWBase::Environment::get().getWorld();

                if (!world->isWaterWalkingCastableOnTarget(target))
                {
                    if (castByPlayer && caster == target)
                        MWBase::Environment::get().getWindowManager()->messageBox ("#{sMagicInvalidEffect}");
                    return false;
                }
                break;
            }
        }
        return true;
    }
}
