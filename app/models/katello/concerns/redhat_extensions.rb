module Katello
  module Concerns
    module RedhatExtensions
      extend ActiveSupport::Concern

      module Overrides
        def medium_uri(host, url = nil)
          kickstart_repo = host.try(:content_facet).try(:kickstart_repository) || host.try(:kickstart_repository)

          if host.try(:content_source) && kickstart_repo.present?
            return URI.parse(kickstart_repo.full_path(host.content_source))
          else
            super(host, url)
          end
        end

        # overwrite foreman method in operatingsystem.rb
        def boot_files_uri(medium, architecture, host = nil)
          return super(medium, architecture, host) unless host.try(:content_source)
          family_class = self.family.constantize
          family_class::PXEFILES.values.collect do |img|
            "#{medium_uri(host)}/#{pxedir}/#{img}"
          end
        end
      end

      included do
        prepend Overrides
      end

      module ClassMethods
        def find_or_create_operating_system(repo)
          os_name = construct_name(repo.distribution_family)
          major, minor = repo.distribution_version.split('.')
          minor ||= '' # treat minor versions as empty string to not confuse with nil

          create_os = lambda { ::Redhat.where(:name => os_name, :major => major, :minor => minor).first_or_create! }

          begin
            create_os.call
          rescue ActiveRecord::RecordInvalid
            create_os.call
          end
        end

        def create_operating_system(name, major, minor)
          params = {
            'name' => name,
            'major' => major.to_s,
            'minor' => minor.to_s,
            'family' => 'Redhat'
          }

          return ::Redhat.create!(params)
        end

        def construct_name(family)
          if family == ::Operatingsystem::REDHAT_ATOMIC_HOST_DISTRO_NAME
            return ::Operatingsystem::REDHAT_ATOMIC_HOST_OS
          elsif family.include? 'Red Hat'
            return 'RedHat'
          else
            return family.tr(' ', '_')
          end
        end
      end

      def kickstart_repos(host)
        distros = distribution_repositories(host)
        if distros && host.content_source
          distros.map do |distro|
            {:id => distro.id, :name => distro.name, :path => distro.full_path(host.content_source)}
          end
        else
          []
        end
      end

      def distribution_repositories(host)
        content_view = host.try(:content_facet).try(:content_view) || host.try(:content_view)
        lifecycle_environment = host.try(:content_facet).try(:lifecycle_environment) || host.try(:lifecycle_environment)

        if content_view && lifecycle_environment && host.os && host.architecture
          Katello::Repository.in_environment(lifecycle_environment).in_content_views([content_view]).
              where(:distribution_version => host.os.release,
                    :distribution_arch => host.architecture.name,
                    :distribution_bootable => true)
        else
          []
        end
      end
    end
  end
end
