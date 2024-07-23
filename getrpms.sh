#!/usr/bin/env bash
set -xeuf -o pipefail

dnf_output="$1"
distro="$2"
release_version="$3"
search_str="$4"
substitute_str="$5"

[[ ! -f "${dnf_output}" ]] && exit 1

dnf_repo_store_dir="${HOME}/.dnf-repos"
distro_repo_cache_dir="${dnf_repo_store_dir}/${distro}-${release_version}"
distro_repo_file="${distro_repo_cache_dir}/dnf_repo.repo"
mkdir -vp "${distro_repo_cache_dir}"

if [[ "${distro}" == 'rocky' ]]; then
    if [[ "$(curl -o /dev/null --silent -Iw '%{http_code}' "https://download.rockylinux.org/pub/rocky/${release_version}/BaseOS/x86_64/os/repodata/repomd.xml")" -eq "200" ]]; then
        baseurl="https://download.rockylinux.org/pub/rocky/${release_version}"
    elif [[ "$(curl -o /dev/null --silent -Iw '%{http_code}' "https://download.rockylinux.org/vault/rocky/${release_version}/BaseOS/x86_64/os/repodata/repomd.xml")" -eq "200" ]]; then
        baseurl="https://download.rockylinux.org/vault/rocky/${release_version}"
    fi
elif [[ "${distro}" == 'centos' ]]; then
    if [[ "${release_version}" == '7.9' ]]; then
        baseurl="https://archive.kernel.org/centos-vault/7.9.2009"
    fi
else
    echo 'Distro unsupported'
    exit 1
fi

if [[ ! -f "${distro_repo_file}" ]]; then
    arch="$(uname -m)"
    repos=(AppStream BaseOS CRB os PowerTools RT updates)
    echo "" > "${distro_repo_file}"
    for repo in "${repos[@]}"; do
        # Abort if repomd.xml is missing:
        if [[ "$(curl -o /dev/null --silent -Iw '%{http_code}' ${baseurl}/${repo}/${arch}/os/repodata/repomd.xml)" -ne "200" && "$(curl -o /dev/null --silent -Iw '%{http_code}' ${baseurl}/${repo}/${arch}/repodata/repomd.xml)" -ne "200" ]]; then
            continue
        fi

        # add repo to list:
        echo -e "[${repo}_${release_version}_${arch}]\nname=${repo}_${release_version}_${arch}\nbaseurl=${baseurl}/${repo}/${arch}/os/\ngpgcheck=0\nenabled=1\n" >> "${distro_repo_file}"
    done
fi

# Remove trailing "os/" folder in the case of centos7:
if [[ "${distro}" == 'centos' ]] && [[ "${release_version}" == '7.9' ]]; then
    sed -i 's,os/$,,' "${distro_repo_file}"
fi

while IFS= read -r line; do
    if ! echo "${line}" | grep -q 'aarch64\|i686\|noarch\|riscv64\|x86_64'; then
        continue
    fi

    rpm_package_name="$(echo "${line}" | awk '{print $1}')"

    rpm_arch="$(echo "${line}" | awk '{print $2}')"
    if [[ "${rpm_arch}" == "${search_str}" ]]; then
        rpm_arch="${substitute_str}"
    fi

    rpm_version_soup="$(echo "${line}" | awk '{print $3}')"
    rpm_version="$(echo "${rpm_version_soup}" | awk -F '-' '{print $1}')"
    rpm_release="$(echo "${rpm_version_soup}" | awk -F '-' '{print $2}')"
    if echo "${rpm_version}" | grep -q ':'; then
        rpm_version="$(echo "${rpm_version}" | awk -F ':' '{print $2}')"
    fi

    full_rpm_name="${rpm_package_name}-${rpm_version}-${rpm_release}.${rpm_arch}.rpm"
    if [[ ! -f "${full_rpm_name}" ]]; then
        dnf_cmd="dnf --setopt=reposdir=${distro_repo_file} --setopt=cachedir=${distro_repo_cache_dir}"
        ${dnf_cmd} check-update --refresh
        dnf_repoquery_cmd="${dnf_cmd} repoquery --queryformat"
        srpm_package_name="$(${dnf_repoquery_cmd} "%{source_name}\n" "${rpm_package_name}")"
        srpm_package_version="$(${dnf_repoquery_cmd} "%{version}\n" "${srpm_package_name}")"
        rpm_download_link="https://kojidev.rockylinux.org/kojifiles/packages/${srpm_package_name}/${srpm_package_version:-$rpm_version}/${rpm_release}/${rpm_arch}/${full_rpm_name}"
        if command -v wget >/dev/null; then
            wget "${rpm_download_link}"
        else
            curl -O "${rpm_download_link}"
        fi
    fi

done < "$dnf_output"
